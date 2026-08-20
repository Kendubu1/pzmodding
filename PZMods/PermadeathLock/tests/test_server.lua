-- Harness: drives PermadeathLock_Server's sweep and client-command handlers
-- against stubbed Project Zomboid globals.

local files = {}
local sent = {}          -- captured sendServerCommand calls
local online = {}        -- players currently "connected"
local handlers = {}      -- captured Events.*.Add callbacks

function isServer() return true end
function isClient() return false end
function getTimestamp() return 1700000000 end
function print(...) end  -- silence the mod's console output

SandboxVars = { PermadeathLock = { Enabled = true, ExemptAdmins = true, EnforceKill = true, RestoreSkillsOnRevive = true } }

Events = setmetatable({}, { __index = function(t, name)
    local slot = {
        Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
        Remove = function() end,
    }
    rawset(t, name, slot)
    return slot
end })

function sendServerCommand(player, module, command, args)
    sent[#sent + 1] = { user = player:getUsername(), command = command, text = args and args.text, args = args }
end

function getOnlinePlayers()
    return { size = function() return #online end, get = function(_, i) return online[i + 1] end }
end

-- As in test_store: the id and the display name differ, because they do in the
-- real game, and getPerkFromName matches the display name only.
local function makePerk(id, displayName)
    return {
        getId = function() return id end,
        getName = function() return displayName or id end,
        getType = function() return "TYPE_" .. id end,
    }
end
local perkList = { makePerk("Woodwork", "Carpentry"), makePerk("Aiming", "Aiming") }
PerkFactory = {
    PerkList = { size = function() return #perkList end, get = function(_, i) return perkList[i + 1] end },
    getPerkFromName = function(name)
        for _, p in ipairs(perkList) do if p.getName() == name then return p end end
    end,
}

function getFileWriter(name, _, append)
    if not append then files[name] = {} end
    files[name] = files[name] or {}
    local lines = files[name]
    return { writeln = function(_, s) lines[#lines + 1] = s end, close = function() end }
end

function getFileReader(name, createIfNull)
    if files[name] == nil then
        if not createIfNull then return nil end
        files[name] = {}
    end
    local lines, i = files[name], 0
    return { readLine = function() i = i + 1 return lines[i] end, close = function() end }
end

--- An inventory holding `tokens` copies of the Fate Token. Removal goes through
--- the item's own container, mirroring how the mod spends one.
local function makeInventory(owner, tokens, nativeLookupBlind)
    local items = {}
    local container
    container = {
        Remove = function(_, item)
            for i, held in ipairs(items) do
                if held == item then table.remove(items, i) return end
            end
        end,
        -- nativeLookupBlind mimics getItemsFromFullType not reaching the item,
        -- which forces the hand-rolled scan to be the thing that finds it.
        getItemsFromFullType = function(_, fullType, _includeInv)
            local hits = {}
            if not nativeLookupBlind then
                for _, item in ipairs(items) do
                    if item.getFullType() == fullType then hits[#hits + 1] = item end
                end
            end
            return { size = function() return #hits end, get = function(_, i) return hits[i + 1] end }
        end,
        getItems = function()
            return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
        end,
    }
    for _ = 1, tokens or 0 do
        items[#items + 1] = {
            getFullType = function() return "Base.FateToken" end,
            getContainer = function() return container end,
            -- Raises if touched: the mod must ask IsInventoryContainer first,
            -- because in Kahlua even a caught error is printed to the log.
            IsInventoryContainer = function() return false end,
            getInventory = function() error("getInventory called on a plain item") end,
        }
    end
    owner._items = items
    return container
end

local function makePlayer(username, opts)
    opts = opts or {}
    local held = {}
    for k, v in pairs(opts.levels or {}) do held[k] = v end
    local self
    self = {
        _dead = opts.dead or false,
        _healed = false,
        _levels = held,
        getUsername = function() return username end,
        getSteamID = function() return "7656119800000000" end,
        isDead = function() return self._dead end,
        isAccessLevel = function(_, level) return opts.admin == true and level == "admin" end,
        getPerkLevel = function(_, t) return held[t] or 0 end,
        LevelPerk = function(_, t) held[t] = (held[t] or 0) + 1 end,
        Kill = function() self._dead = true end,
        getBodyDamage = function()
            return { RestoreToFullHealth = function() self._healed = true end }
        end,
    }
    self.getInventory = function() return self._container end
    self._container = makeInventory(self, opts.tokens, opts.nativeLookupBlind)
    return self
end

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")
-- Loaded in the order the game loads them: alphabetically, so Server.lua runs
-- BEFORE Store.lua. Loading Store first here would hide load-order bugs.
dofile("PZMods/PermadeathLock/42/media/lua/server/PermadeathLock_Server.lua")
dofile("PZMods/PermadeathLock/42/media/lua/server/PermadeathLock_Store.lua")

local Store = PermadeathLock.Store
local MODULE = PermadeathLock.MODULE
local sweep = handlers["EveryOneMinute"][1]
local onClientCommand = handlers["OnClientCommand"][1]

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        io.write(string.format("FAIL  %-52s got=%s want=%s\n", label, tostring(got), tostring(want)))
    else
        io.write(string.format("ok    %-52s %s\n", label, tostring(got)))
    end
end

local function lastCommandTo(user)
    for i = #sent, 1, -1 do
        if sent[i].user == user then return sent[i].command end
    end
end

local function reset()
    files, sent, online = {}, {}, {}
    Store.load()
    Store.clear()
end

--------------------------------------------------------------------------------
reset()
io.write("-- death detection --\n")

local bob = makePlayer("Bob", { levels = { TYPE_Woodwork = 5 }, dead = true })
online = { bob }
sweep()
check("sweep records a dead player", Store.isLocked("Bob"), true)
check("skills captured by the sweep", Store.get("Bob").skills["Woodwork"], 5)

-- an admin dying is ignored while ExemptAdmins is on
local boss = makePlayer("Boss", { admin = true, dead = true })
online = { boss }
sweep()
check("exempt admin is not recorded", Store.isLocked("Boss"), false)

--------------------------------------------------------------------------------
io.write("\n-- blocking a returning player --\n")

local bobNew = makePlayer("Bob", {})
online = { bobNew }
sweep()
check("first sweep asks them to leave", lastCommandTo("Bob"), "blocked")
check("first sweep does not kill", bobNew._dead, false)
sweep()
check("second sweep kills a client that stayed", bobNew._dead, true)

-- the spawn handshake blocks immediately, without waiting for a sweep
sent = {}
local bobAgain = makePlayer("Bob", {})
onClientCommand(MODULE, "checkStatus", bobAgain, {})
check("checkStatus blocks on spawn", lastCommandTo("Bob"), "blocked")

--------------------------------------------------------------------------------
io.write("\n-- revive --\n")

Store.revive("Bob")
sent = {}
local bobRevived = makePlayer("Bob", {})
onClientCommand(MODULE, "checkStatus", bobRevived, {})
check("revived player is not blocked", lastCommandTo("Bob"), "message")
check("revived player gets their skills", bobRevived._levels.TYPE_Woodwork, 5)
check("record cleared after restore", Store.get("Bob"), nil)

-- regression: an exempt admin must still receive a queued restore
reset()
local adminDead = makePlayer("Boss", { levels = { TYPE_Aiming = 3 } })
Store.record(adminDead, "test")          -- recorded while not exempt
Store.revive("Boss")
local adminBack = makePlayer("Boss", { admin = true })
online = { adminBack }
sweep()
check("exempt admin still gets a queued restore", adminBack._levels.TYPE_Aiming, 3)
check("admin record cleared after restore", Store.get("Boss"), nil)

-- a dead character must not consume the restore
reset()
local cara = makePlayer("Cara", { levels = { TYPE_Aiming = 4 } })
Store.record(cara, "test")
Store.revive("Cara")
local caraDead = makePlayer("Cara", { dead = true })
onClientCommand(MODULE, "checkStatus", caraDead, {})
check("restore not spent on a dead character", Store.get("Cara") ~= nil, true)
check("restore still pending", Store.get("Cara").pendingRestore, true)

--------------------------------------------------------------------------------
io.write("\n-- dying again after a revive --\n")

reset()
local dee = makePlayer("Dee", { levels = { TYPE_Woodwork = 2 } })
Store.record(dee, "first death")
Store.revive("Dee")
local deeNew = makePlayer("Dee", {})
online = { deeNew }
sweep()
check("restore applied", deeNew._levels.TYPE_Woodwork, 2)
deeNew._dead = true
sweep()
check("second death re-locks them", Store.isLocked("Dee"), true)

--------------------------------------------------------------------------------
io.write("\n-- the notice sent at the moment of death --\n")

reset()
sent = {}
local pat = makePlayer("Pat", { dead = true })
online = { pat }
sweep()
check("dying with no token is announced to the player", lastCommandTo("Pat"), "fateSealed")

reset()
sent = {}
local quin = makePlayer("Quin", { dead = true, tokens = 1 })
online = { quin }
sweep()
check("dying with a token announces the token instead", lastCommandTo("Quin"), "tokenSpent")

--------------------------------------------------------------------------------
io.write("\n-- admin command authorisation --\n")

reset()
Store.addManual("Target", "test")
sent = {}
local nobody = makePlayer("Nobody", {})
onClientCommand(MODULE, "admin", nobody, { sub = "pardon", target = "Target" })
check("non-admin cannot pardon", Store.isLocked("Target"), true)

sent = {}
local admin = makePlayer("Admin", { admin = true })
onClientCommand(MODULE, "admin", admin, { sub = "pardon", target = "Target" })
check("admin can pardon", Store.isLocked("Target"), false)

-- clear needs the confirm word
Store.addManual("One"); Store.addManual("Two")
onClientCommand(MODULE, "admin", admin, { sub = "clear" })
check("clear without confirm is refused", Store.count(), 2)
onClientCommand(MODULE, "admin", admin, { sub = "clear", target = "confirm" })
check("clear with confirm wipes", Store.count(), 0)

-- REGRESSION: pardoning a player whose character is still lying dead in the
-- world used to be undone by the very next sweep. The sweep records any dead
-- player it finds with no record, so a minute after the pardon they were back
-- on the list - and were then blocked when they made a new character, which is
-- exactly the "I cleared myself and still cannot spawn in" report.
reset()
local rae = makePlayer("Rae", { dead = true })
online = { rae }
sweep()
check("Rae is locked out after dying", Store.isLocked("Rae"), true)
onClientCommand(MODULE, "admin", admin, { sub = "pardon", target = "Rae" })
check("pardon takes them off the list", Store.get("Rae"), nil)
sweep()                                   -- corpse still standing there
check("the next sweep does not re-record them", Store.get("Rae"), nil)
sweep()
check("nor the sweep after that", Store.get("Rae"), nil)

-- and once they are back on their feet a fresh death counts again
rae._dead = false
sweep()
rae._dead = true
sweep()
check("a death after the pardon still locks them", Store.isLocked("Rae"), true)

-- the same trap for a whole-list wipe
reset()
local sam = makePlayer("Sam", { dead = true })
online = { sam }
sweep()
check("Sam is locked out after dying", Store.isLocked("Sam"), true)
onClientCommand(MODULE, "admin", admin, { sub = "clear", target = "confirm" })
sweep()
check("clear all is not undone by the next sweep", Store.count(), 0)

-- but pardoning someone who is OFFLINE must not excuse a later death
reset()
Store.addManual("Tess", "test")
online = {}
onClientCommand(MODULE, "admin", admin, { sub = "pardon", target = "Tess" })
local tess = makePlayer("Tess", { dead = true })
online = { tess }
sweep()
check("offline pardon does not excuse the next death", Store.isLocked("Tess"), true)

-- reviving someone who is online and alive heals them on the spot
reset()
local eve = makePlayer("Eve", { levels = { TYPE_Aiming = 6 } })
Store.record(eve, "test")
local eveNew = makePlayer("Eve", {})
online = { eveNew }
onClientCommand(MODULE, "admin", admin, { sub = "revive", target = "eve" })
check("online revive restores skills", eveNew._levels.TYPE_Aiming, 6)
check("online revive heals", eveNew._healed, true)

--------------------------------------------------------------------------------
io.write("\n-- fate tokens --\n")

reset()
local gil = makePlayer("Gil", { levels = { TYPE_Woodwork = 7 }, dead = true, tokens = 1 })
online = { gil }
sweep()
check("token holder is recorded", Store.get("Gil") ~= nil, true)
check("token holder is NOT locked out", Store.isLocked("Gil"), false)
check("token queues a restore", Store.get("Gil").pendingRestore, true)
check("token is consumed", #gil._items, 0)
check("death reason names the token", Store.get("Gil").reason, PermadeathLock.REASON_TOKEN)
check("skills captured before the save", Store.get("Gil").skills["Woodwork"], 7)

-- the saved player walks straight back in and collects their skills
local gilNew = makePlayer("Gil", {})
online = { gilNew }
sent = {}
sweep()
check("saved player is not blocked", lastCommandTo("Gil"), "message")
check("saved player keeps their skills", gilNew._levels.TYPE_Woodwork, 7)
check("record cleared after the save is spent", Store.get("Gil"), nil)

-- second death with no token left: locked as normal
gilNew._dead = true
online = { gilNew }
sweep()
check("no second save without a token", Store.isLocked("Gil"), true)

-- only one token is spent per death
reset()
local hana = makePlayer("Hana", { dead = true, tokens = 3 })
online = { hana }
sweep()
check("exactly one token spent", #hana._items, 2)

-- with consumption disabled the token stays on the body
reset()
SandboxVars.PermadeathLock.FateTokenConsume = false
local ivan = makePlayer("Ivan", { dead = true, tokens = 1 })
online = { ivan }
sweep()
check("token kept when consumption is off", #ivan._items, 1)
check("still saved when consumption is off", Store.isLocked("Ivan"), false)
SandboxVars.PermadeathLock.FateTokenConsume = true

-- with the token disabled entirely it is ignored
reset()
SandboxVars.PermadeathLock.FateTokenEnabled = false
local jo = makePlayer("Jo", { dead = true, tokens = 1 })
online = { jo }
sweep()
check("token ignored when disabled", Store.isLocked("Jo"), true)
check("disabled token is not consumed", #jo._items, 1)
SandboxVars.PermadeathLock.FateTokenEnabled = true

-- the client death report takes the same path as the sweep
reset()
local kim = makePlayer("Kim", { dead = true, tokens = 1 })
onClientCommand(MODULE, "reportDeath", kim, {})
check("reportDeath honours the token", Store.isLocked("Kim"), false)
check("reportDeath consumes the token", #kim._items, 0)

-- the hand-rolled scan finds it when the native lookup does not
reset()
local lena = makePlayer("Lena", { dead = true, tokens = 1, nativeLookupBlind = true })
online = { lena }
sweep()
check("manual scan finds the token", Store.isLocked("Lena"), false)
check("manual scan consumes the token", #lena._items, 0)

-- REGRESSION: the corpse has already taken the inventory by the time the sweep
-- notices the death. The token must still count, from the last living sweep.
reset()
local milo = makePlayer("Milo", { levels = { TYPE_Aiming = 4 }, tokens = 1 })
online = { milo }
sweep()                                   -- seen alive, carrying a token
milo._dead = true
milo._container = makeInventory(milo, 0)  -- corpse took everything
sweep()
check("death after inventory moved still counts", Store.isLocked("Milo"), false)
check("remembered save still queues a restore", Store.get("Milo").pendingRestore, true)
check("remembered save keeps the skills", Store.get("Milo").skills["Aiming"], 4)

-- but an empty-handed player is still locked out, cache or no cache
reset()
local nia = makePlayer("Nia", { tokens = 0 })
online = { nia }
sweep()
nia._dead = true
sweep()
check("no token means locked out", Store.isLocked("Nia"), true)

--------------------------------------------------------------------------------
io.write("\n-- the admin panel's data feed --\n")

reset()
local sara = makePlayer("Sara", { levels = { TYPE_Woodwork = 3, TYPE_Aiming = 1 }, dead = true })
online = { sara }
sweep()

sent = {}
local panelAdmin = makePlayer("Admin", { admin = true })
onClientCommand(MODULE, "admin", panelAdmin, { sub = "listdata" })
local payload = sent[#sent]
check("listData answers an admin", payload.command, "listData")
check("one row per record", #payload.args.rows, 1)
check("the row names the player", payload.args.rows[1].username, "Sara")
check("and counts their skills", payload.args.rows[1].skills, 2)
check("and reports them locked", payload.args.rows[1].locked, true)
check("the payload carries the version", payload.args.version, PermadeathLock.VERSION)

sent = {}
onClientCommand(MODULE, "admin", makePlayer("Nobody", {}), { sub = "listdata" })
check("but not a non-admin", sent[1] and sent[1].command, "message")

--------------------------------------------------------------------------------
io.write("\n-- disabling the mod --\n")

reset()
SandboxVars.PermadeathLock.Enabled = false
local frank = makePlayer("Frank", { dead = true })
online = { frank }
sweep()
check("no recording while disabled", Store.isLocked("Frank"), false)
SandboxVars.PermadeathLock.Enabled = true

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
