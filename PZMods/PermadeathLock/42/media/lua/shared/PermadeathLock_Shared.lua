--[[
    Permadeath Lock - shared definitions.

    Loaded on both the client and the server. Holds the network module name, the
    sandbox option accessors and the username handling that both sides must agree
    on, so a lookup done on the server matches a name typed by an admin.
]]

PermadeathLock = PermadeathLock or {}
local PL = PermadeathLock

PL.VERSION = "1.14.2"

-- Module name used by sendClientCommand / sendServerCommand.
PL.MODULE = "PermadeathLock"

-- Death list, written to Zomboid/Lua/ on the server. Plain text so an admin can
-- read or edit it with the server down, then use /permadeath reload.
PL.DEATH_FILE = "PermadeathLock_deaths.txt"

-- The death list's table is created here, not in PermadeathLock_Store.lua, and
-- this matters. The game loads a folder's Lua files alphabetically, so
-- PermadeathLock_Server.lua runs BEFORE PermadeathLock_Store.lua. Anything doing
-- `local Store = PL.Store` at load time in Server.lua would capture nil forever
-- and blow up on the first sweep. Creating the table in shared - which loads
-- before both - means every file captures the same table whatever the order.
PL.Store = PL.Store or {}

-- The bind registry's table, created here for exactly the same reason.
PL.Binds = PL.Binds or {}

-- Where the bind registry is written, next to the death list and in the same
-- readable plain text.
PL.BIND_FILE = "PermadeathLock_binds.txt"

-- The Fate Token. Dying while carrying one spends it instead of locking you out.
PL.FATE_TOKEN = "Base.FateToken"

-- Recorded as the death reason when a token was spent, so the restore can tell
-- the player what saved them.
PL.REASON_TOKEN = "spent a Fate Token"

--- Co-op host detection, guarded in case the global is missing on some builds.
---@return boolean
local function coopHost()
    if isCoopHost == nil then return false end
    local ok, value = pcall(isCoopHost)
    return ok and value == true
end

--- Exposed so the boot line can report it. See isServerSide.
---@return boolean
function PL.isCoopHost() return coopHost() end

--- Where the authoritative logic runs: a dedicated server, or the host of a
--- co-op game, who runs the server in-process. False in single player, which
--- the mod deliberately leaves alone.
---
--- The isClient() exclusion is the important part, and it was learned the hard
--- way. **A co-op Host game runs two Lua states in one process** - the
--- in-process server, and the host's own client - and isCoopHost() is true in
--- BOTH of them. Gating on it alone loaded the whole server half twice: two
--- death lists, two sweeps, two Fate Token caches, both writing the same file.
---
--- What that looked like from the outside was a single death being evaluated
--- twice, a fifth of a second apart, with opposite verdicts:
---
---   death of Willy: token on body=true,  ... not locked out. Token consumed.
---   death of Willy: token on body=false, ... and is locked out. No Fate Token.
---
--- The first state found the token and spent it. The second ran afterwards,
--- found nothing left to find, and locked the player out - who was then killed
--- by the enforcement a few seconds after respawning. The rescue was what
--- killed them.
---
--- Whichever state is a client is never the one that should be arbitrating.
---@return boolean
function PL.isServerSide()
    if isClient() then return false end
    return isServer() or coopHost()
end

--- Where the player-facing logic runs: a connected client, or the co-op host,
--- who is both the server and a player.
---
--- Mirror of the exclusion above, for the same reason: the state that is the
--- server is not the one with a player sitting in front of it.
---@return boolean
function PL.isClientSide()
    if isServer() then return false end
    return isClient() or coopHost()
end

--- Read a sandbox option, falling back to a default if the options failed to load.
---@param name string
---@param default any
---@return any
function PL.getOption(name, default)
    local vars = SandboxVars and SandboxVars.PermadeathLock
    if vars == nil then return default end
    local value = vars[name]
    if value == nil then return default end
    return value
end

---@return boolean
function PL.isEnabled()
    return PL.getOption("Enabled", true) == true
end

--- Normalise a username into the key used by the death list.
--- Usernames are matched case-insensitively so an admin does not have to
--- reproduce the exact capitalisation when pardoning someone.
---@param username string?
---@return string? key nil when the username is missing or blank
function PL.key(username)
    if username == nil then return nil end

    local trimmed = string.match(tostring(username), "^%s*(.-)%s*$")
    if trimmed == nil or trimmed == "" then return nil end

    -- Surrounding quotes are stripped here as well as in the chat parser. Names
    -- with spaces get quoted by hand, and a lookup for '"Willy Guggenheim"'
    -- silently missing a record stored as 'Willy Guggenheim' is the kind of
    -- failure that looks like the death list being broken.
    local unquoted = string.match(trimmed, '^"(.*)"$') or string.match(trimmed, "^'(.*)'$")
    if unquoted ~= nil and unquoted ~= "" then trimmed = unquoted end

    return string.lower(trimmed)
end

--------------------------------------------------------------------------------
-- finding fate tokens
--------------------------------------------------------------------------------
--
-- Shared rather than server-only so either half can ask, though in practice the
-- server does all of it: it counts a player's tokens for the admin panel, spends
-- one on death, and adds or removes one when an admin hands it out.
--
-- Handing out used to be done by the target's client, on the reasoning that a
-- player's inventory belongs to their own machine. In Build 42 it does not: the
-- client added the item, the server never saw it, and the death check - which
-- reads the server's inventory - let the player be locked out while carrying
-- three tokens. Inventory changes are made server-side, as vanilla's /additem
-- does.

local scanTokens

--- Walk a container and its bags by hand, collecting every token found.
---@param container ItemContainer?
---@param depth integer
---@param found InventoryItem[]
scanTokens = function(container, depth, found)
    if container == nil or depth > 3 then return end

    local items = container:getItems()
    if items == nil then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= nil then
            if item:getFullType() == PL.FATE_TOKEN then
                found[#found + 1] = item
            end
            -- Ask before descending. Calling getInventory on a plain item
            -- raises, and a pcall around it is NOT quiet: Kahlua prints the
            -- stack trace even when the error is caught, which floods the
            -- server log once per item per sweep.
            if item:IsInventoryContainer() then
                scanTokens(item:getInventory(), depth + 1, found)
            end
        end
    end
end

--- Where one token brings you back, if it has been bound.
---
--- Kept on the ITEM, not against the player. Each token carries its own
--- coordinate, so a player can hold several bound to different places and know
--- which is which, and an unbound one is simply a token with nothing written on
--- it. Item mod data travels with the item - drop it, trade it, leave it in a
--- crate, and the binding goes with it.
---@param item InventoryItem?
---@return table? bind
function PL.getTokenBind(item)
    if item == nil or item.getModData == nil then return nil end

    local data = item:getModData()
    if data == nil then return nil end

    local x, y = tonumber(data.pdlBindX), tonumber(data.pdlBindY)
    if x == nil or y == nil then return nil end
    return { x = x, y = y, z = tonumber(data.pdlBindZ) or 0 }
end

--- The registry number written on one token, if it has been given one.
---
--- A bind lives in two places: on the item, and in the server's registry. The
--- item is the copy that matters while someone is holding it; the registry is
--- the copy that survives the item being dropped in a bag in a house nobody
--- goes back to. This number is what ties the two together.
---@param item InventoryItem?
---@return number? id
function PL.getTokenId(item)
    if item == nil or item.getModData == nil then return nil end

    local data = item:getModData()
    if data == nil then return nil end
    return tonumber(data.pdlTokenId)
end

---@param item InventoryItem
---@param id number
function PL.setTokenId(item, id)
    if item == nil or item.getModData == nil then return end

    local data = item:getModData()
    if data == nil then return end
    data.pdlTokenId = id
end

---@param item InventoryItem
---@param x number
---@param y number
---@param z number?
function PL.setTokenBind(item, x, y, z)
    if item == nil or item.getModData == nil then return end

    local data = item:getModData()
    if data == nil then return end

    data.pdlBindX = math.floor(x)
    data.pdlBindY = math.floor(y)
    data.pdlBindZ = math.floor(z or 0)
end

--- Every Fate Token on a character, bags included.
--- Matched by full type, so there is no ambiguity with a similarly named item
--- from another mod.
---@param player IsoPlayer?
---@return InventoryItem[]
function PL.findTokens(player)
    if player == nil then return {} end

    local inventory = player:getInventory()
    if inventory == nil then return {} end

    -- The native lookup first, because it is the one the game maintains. The
    -- hand-rolled scan is a backstop for it not reaching inside nested bags.
    local ok, native = pcall(function()
        return inventory:getItemsFromFullType(PL.FATE_TOKEN, true)
    end)
    if ok and native ~= nil and native:size() > 0 then
        local found = {}
        for i = 0, native:size() - 1 do
            found[#found + 1] = native:get(i)
        end
        return found
    end

    local found = {}
    pcall(scanTokens, inventory, 0, found)
    return found
end

---@param player IsoPlayer?
---@return InventoryItem?
function PL.findToken(player)
    return PL.findTokens(player)[1]
end

---@param player IsoPlayer?
---@return integer
function PL.countTokens(player)
    return #PL.findTokens(player)
end

--- The height of one line of UIFont.Small.
---
--- Client-side only in practice, and the single number every piece of this
--- mod's UI is sized from. The game's UI Scaling setting changes every glyph on
--- screen, so anything measured in pixels is right on one machine and wrong on
--- the next: the admin panel had its bands collapse into each other at 2x, and
--- the death notices had their text overflow a box built for 1x.
---@return integer
function PL.textHeight()
    local FALLBACK = 14
    if getTextManager == nil then return FALLBACK end

    local manager = getTextManager()
    if manager == nil then return FALLBACK end

    local height = manager:getFontHeight(UIFont.Small)
    if height == nil or height <= 0 then return FALLBACK end
    return height
end

--- Players the lock never applies to.
---@param player IsoPlayer?
---@return boolean
function PL.isExempt(player)
    if player == nil then return true end
    if PL.getOption("ExemptAdmins", true) and player:isAccessLevel("admin") then
        return true
    end
    return false
end
