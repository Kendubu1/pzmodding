--[[
    Permadeath Lock - server enforcement and admin commands.

    Runs on a dedicated server, and on the host of a co-op game (who runs the
    server in-process). Single player is left alone.

    Two paths record and enforce a death, because neither is sufficient alone:

      * The client reports its own death and asks for its status when it spawns.
        This is the fast, polite path: the player gets an explanation and their
        client disconnects itself.

      * A sweep over getOnlinePlayers() every in-game minute. The game exposes no
        server-side "player connected" event and no kick function to Lua, so this
        is the only enforcement a modified client cannot opt out of.

    Sandbox option EnforceKill decides what happens to a locked-out player whose
    client ignored the disconnect request: by default they are killed again, which
    is the strongest action available to server Lua.
]]

if not PermadeathLock.isServerSide() then return end

local PL = PermadeathLock
local Store = PL.Store
local MODULE = PL.MODULE

-- How many sweeps a locked-out player has survived since we asked them to leave.
---@type table<string, integer>
local strikes = {}

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

---@param player IsoPlayer
---@param text string
local function tell(player, text)
    sendServerCommand(player, MODULE, "message", { text = text })
end

---@param player IsoPlayer
---@param record table?
local function sendBlocked(player, record)
    sendServerCommand(player, MODULE, "blocked", {
        username = player:getUsername(),
        time = record and record.time or 0,
    })
end

---@param username string?
---@return IsoPlayer?
local function findOnline(username)
    local key = PL.key(username)
    if key == nil then return nil end

    local players = getOnlinePlayers()
    if players == nil then return nil end

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player ~= nil and PL.key(player:getUsername()) == key then
            return player
        end
    end
    return nil
end

---@param timestamp integer?
---@return string
local function describeAge(timestamp)
    if timestamp == nil or timestamp == 0 then return "unknown" end
    local hours = math.floor((getTimestamp() - timestamp) / 3600)
    if hours < 1 then return "under an hour ago" end
    if hours < 48 then return hours .. "h ago" end
    return math.floor(hours / 24) .. "d ago"
end

--------------------------------------------------------------------------------
-- fate tokens
--------------------------------------------------------------------------------

-- Whether each player was carrying a token when last seen ALIVE. A death is
-- often only noticed by the sweep a second or two after the fact, by which time
-- the corpse has taken the inventory and the token is no longer reachable from
-- the player. Without this, a token that was definitely being carried finds
-- nothing and the player is wrongly locked out.
---@type table<string, boolean>
local carriedToken = {}

local scanForToken

--- Walk a container and its bags by hand. A backstop for the native lookup,
--- which we do not want to depend on for reaching inside nested containers.
---@param container ItemContainer?
---@param depth integer
---@return InventoryItem?
scanForToken = function(container, depth)
    if container == nil or depth > 3 then return nil end

    local items = container:getItems()
    if items == nil then return nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= nil then
            if item:getFullType() == PL.FATE_TOKEN then return item end
            -- Ask before descending. Calling getInventory on a plain item raises,
            -- and a pcall around it is NOT quiet: Kahlua prints the stack trace
            -- even when the error is caught, which floods the server log once
            -- per item per sweep.
            if item:IsInventoryContainer() then
                local nested = item:getInventory()
                if nested ~= nil then
                    local found = scanForToken(nested, depth + 1)
                    if found ~= nil then return found end
                end
            end
        end
    end
    return nil
end

--- Find a Fate Token anywhere on the character, bags included.
--- Searched by full type so there is no ambiguity with a similarly named item
--- from another mod.
---@param player IsoPlayer
---@return InventoryItem?
local function findFateToken(player)
    local inventory = player:getInventory()
    if inventory == nil then return nil end

    local ok, found = pcall(function()
        return inventory:getItemsFromFullType(PL.FATE_TOKEN, true)
    end)
    if ok and found ~= nil and found:size() > 0 then return found:get(0) end

    local scanned
    ok, scanned = pcall(scanForToken, inventory, 0)
    if ok then return scanned end
    return nil
end

--- Note whether a LIVING player is carrying a token. Never called for the dead:
--- their inventory has usually moved to the corpse, and recording "no token"
--- then would erase what we learned while they were alive.
---@param player IsoPlayer
local function rememberToken(player)
    if player:isDead() then return end

    local key = PL.key(player:getUsername())
    if key == nil then return end
    carriedToken[key] = findFateToken(player) ~= nil
end

--- Burn the token. Failure is not fatal: the save is already earned, and the
--- corpse keeping the item is a smaller problem than denying the rescue.
---@param item InventoryItem
---@return boolean removed
local function consumeFateToken(item)
    local container = item:getContainer()
    if container == nil then return false end
    container:Remove(item)
    return true
end

---@param player IsoPlayer
---@param reason string
local function recordDeath(player, reason)
    if not PL.isEnabled() then return end
    if PL.isExempt(player) then return end
    -- Already on the list: the token was either spent or not needed.
    if Store.get(player:getUsername()) ~= nil then return end

    local key = PL.key(player:getUsername())
    local token, remembered = nil, false
    if PL.getOption("FateTokenEnabled", true) then
        token = findFateToken(player)
        remembered = carriedToken[key] == true
    end

    if token == nil and not remembered then
        local record = Store.record(player, reason)
        if record ~= nil then
            print("[PermadeathLock] " .. record.username .. " died (" .. reason
                .. ") and is locked out. No Fate Token on the body or in their last living inventory.")
        end
        carriedToken[key] = nil
        return
    end

    local burned = false
    if token ~= nil and PL.getOption("FateTokenConsume", true) then
        burned = consumeFateToken(token)
    end

    local record = Store.record(player, PL.REASON_TOKEN, true)
    if record ~= nil then
        -- A modal, not a chat line: this lands as the player dies, and the chat
        -- window is not on screen behind the death UI.
        sendServerCommand(player, MODULE, "tokenSpent", {})

        local how
        if token == nil then
            how = " Found in their last living inventory, not on the body, so it could not be removed."
        elseif burned then
            how = " Token consumed."
        else
            how = " WARNING: the token could not be removed from the body."
        end
        print("[PermadeathLock] " .. record.username .. " died holding a Fate Token; not locked out." .. how)
    end
    carriedToken[key] = nil
end

--- Hand a revived player's queued skills to the character they are now playing.
---@param player IsoPlayer
---@param record table
local function applyRestore(player, record)
    local raised = 0
    if PL.getOption("RestoreSkillsOnRevive", true) then
        raised = Store.applySkills(player, record.skills)
    end
    Store.finishRestore(record.username)
    strikes[PL.key(record.username)] = nil

    local source = "An admin brought you back."
    if record.reason == PL.REASON_TOKEN then
        source = "Your Fate Token paid for this life."
    end

    if raised > 0 then
        tell(player, source .. " " .. raised .. " skill(s) restored from your last character.")
    else
        tell(player, source .. " Try to stay alive this time.")
    end
    print("[PermadeathLock] Restored " .. record.username .. " (" .. raised .. " skills).")
end

--------------------------------------------------------------------------------
-- enforcement sweep
--------------------------------------------------------------------------------

---@param player IsoPlayer
local function checkPlayer(player)
    local username = player:getUsername()
    if PL.key(username) == nil then return end

    local record = Store.get(username)

    -- Alive, and an admin has cleared them: this is the new character. Checked
    -- before the exemption, because a queued restore is owed to the player
    -- whatever their access level - an admin who becomes exempt after being
    -- revived should still get their skills back.
    if record ~= nil and record.pendingRestore and not player:isDead() then
        applyRestore(player, record)
        return
    end

    if PL.isExempt(player) then return end

    if player:isDead() then
        recordDeath(player, "died")
        return
    end

    -- Alive: note whether they are carrying a token, so a death spotted after
    -- the corpse has taken the inventory still counts.
    rememberToken(player)

    if record == nil or not record.locked then return end

    -- Alive while locked out means they made a new character. Ask once, then act.
    local key = PL.key(username)
    strikes[key] = (strikes[key] or 0) + 1

    if strikes[key] == 1 then
        sendBlocked(player, record)
        print("[PermadeathLock] " .. username .. " rejoined after death; asked to disconnect.")
    elseif PL.getOption("EnforceKill", true) then
        player:Kill(player)
        print("[PermadeathLock] " .. username .. " ignored the block; new character killed.")
    end
end

local function sweep()
    if not PL.isEnabled() then return end

    local players = getOnlinePlayers()
    if players == nil then return end

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player ~= nil then checkPlayer(player) end
    end
end

Events.EveryOneMinute.Add(sweep)

--------------------------------------------------------------------------------
-- admin commands
--------------------------------------------------------------------------------

local HELP = {
    "/permadeath status            - is the lock on, and how many are locked out",
    "/permadeath list              - show the death list",
    "/permadeath ui                - open the admin panel",
    "/permadeath revive <user>     - bring a player back, keeping their skills",
    "/permadeath pardon <user>     - let a player back in, from scratch",
    "/permadeath add <user>        - lock a player out by hand",
    "/permadeath clear confirm     - wipe the whole death list",
    "/permadeath reload            - re-read the death list from disk",
}

---@param player IsoPlayer
local function sendHelp(player)
    tell(player, "Permadeath Lock " .. PL.VERSION .. " commands:")
    for _, line in ipairs(HELP) do tell(player, line) end
end

---@param admin IsoPlayer
---@param target string?
local function commandRevive(admin, target)
    if target == nil then
        tell(admin, "Usage: /permadeath revive <username>")
        return
    end

    local record = Store.revive(target)
    if record == nil then
        tell(admin, target .. " is not on the death list.")
        return
    end
    strikes[PL.key(record.username)] = nil

    local online = findOnline(record.username)
    if online == nil then
        tell(admin, record.username .. " revived. Their skills will be restored when they next log in.")
    elseif online:isDead() then
        -- The game exposes no way to un-kill a character, so the body stays dead.
        tell(admin, record.username .. " revived, but their current character is already dead - the game gives no way")
        tell(admin, "to undo that. Tell them to reconnect; their skills will be restored to the new character.")
    else
        applyRestore(online, record)
        online:getBodyDamage():RestoreToFullHealth()
        tell(admin, record.username .. " revived, healed, and their skills restored.")
    end
    print("[PermadeathLock] " .. admin:getUsername() .. " revived " .. record.username .. ".")
end

---@param admin IsoPlayer
---@param target string?
local function commandPardon(admin, target)
    if target == nil then
        tell(admin, "Usage: /permadeath pardon <username>")
        return
    end

    if not Store.pardon(target) then
        tell(admin, target .. " is not on the death list.")
        return
    end
    strikes[PL.key(target)] = nil
    tell(admin, target .. " pardoned. They may rejoin with a fresh character.")
    print("[PermadeathLock] " .. admin:getUsername() .. " pardoned " .. target .. ".")
end

--- The death list as data, for the admin panel to render. The chat `list`
--- command sends prose; this sends rows.
---@param admin IsoPlayer
local function commandListData(admin)
    local rows = {}
    for _, record in ipairs(Store.all()) do
        local count = 0
        for _ in pairs(record.skills or {}) do count = count + 1 end
        rows[#rows + 1] = {
            username = record.username,
            age = describeAge(record.time),
            locked = record.locked == true,
            pendingRestore = record.pendingRestore == true,
            skills = count,
            online = findOnline(record.username) ~= nil,
        }
    end

    sendServerCommand(admin, MODULE, "listData", {
        version = PL.VERSION,
        enabled = PL.isEnabled(),
        tokens = PL.getOption("FateTokenEnabled", true) == true,
        rows = rows,
    })
end

---@param admin IsoPlayer
local function commandList(admin)
    local all = Store.all()
    if #all == 0 then
        tell(admin, "Nobody is on the death list.")
        return
    end

    tell(admin, "Death list (" .. #all .. "):")
    for _, record in ipairs(all) do
        local state = record.locked and "locked" or "awaiting restore"
        tell(admin, " - " .. record.username .. " (" .. state .. ", " .. describeAge(record.time) .. ", " .. (record.reason or "") .. ")")
    end
end

---@param player IsoPlayer
---@param args table
local function handleAdmin(player, args)
    if not player:isAccessLevel("admin") then
        tell(player, "You need admin access to use /permadeath.")
        return
    end

    local sub = string.lower(tostring(args.sub or "status"))
    local target = args.target

    if sub == "status" then
        local state = PL.isEnabled() and "ON" or "OFF"
        tell(player, "Permadeath Lock " .. PL.VERSION .. " is " .. state .. ". " .. Store.count() .. " player(s) on the death list.")
    elseif sub == "list" then
        commandList(player)
    elseif sub == "listdata" then
        commandListData(player)
    elseif sub == "revive" then
        commandRevive(player, target)
    elseif sub == "pardon" then
        commandPardon(player, target)
    elseif sub == "add" then
        if target == nil then
            tell(player, "Usage: /permadeath add <username>")
        elseif Store.addManual(target, "added by " .. player:getUsername()) then
            tell(player, target .. " added to the death list.")
        else
            tell(player, target .. " is already on the death list.")
        end
    elseif sub == "clear" then
        if target ~= "confirm" then
            tell(player, "This wipes all " .. Store.count() .. " record(s). Run: /permadeath clear confirm")
        else
            local removed = Store.clear()
            strikes = {}
            tell(player, "Death list cleared (" .. removed .. " record(s) removed).")
            print("[PermadeathLock] " .. player:getUsername() .. " cleared the death list.")
        end
    elseif sub == "reload" then
        Store.load()
        tell(player, "Death list reloaded: " .. Store.count() .. " record(s).")
    else
        sendHelp(player)
    end
end

--------------------------------------------------------------------------------
-- client commands
--------------------------------------------------------------------------------

---@param module string
---@param command string
---@param player IsoPlayer
---@param args table?
local function onClientCommand(module, command, player, args)
    if module ~= MODULE or player == nil then return end
    args = args or {}

    if command == "admin" then
        -- Access is re-checked here: the client asking is never trusted.
        handleAdmin(player, args)
        return
    end

    if not PL.isEnabled() then return end

    if command == "checkStatus" then
        local record = Store.get(player:getUsername())
        if record == nil then return end
        -- As in the sweep: a queued restore is honoured even for exempt players.
        if record.pendingRestore and not player:isDead() then
            applyRestore(player, record)
        elseif record.locked and not PL.isExempt(player) then
            sendBlocked(player, record)
        end
        return
    end

    if PL.isExempt(player) then return end

    if command == "reportDeath" then
        -- The client reports the instant it dies. If the server has not caught
        -- up yet this is the last chance to see the inventory intact, so take a
        -- snapshot either way; rememberToken is a no-op once they are dead.
        rememberToken(player)
        -- Verified against the character's real state rather than taken on trust.
        if player:isDead() then recordDeath(player, "died") end
    end
end

Events.OnClientCommand.Add(onClientCommand)

print("[PermadeathLock] Server module " .. PL.VERSION .. " loaded.")
