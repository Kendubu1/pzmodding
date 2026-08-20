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
    sent[#sent + 1] = { user = player:getUsername(), command = command, text = args and args.text }
end

function getOnlinePlayers()
    return { size = function() return #online end, get = function(_, i) return online[i + 1] end }
end

local function makePerk(id)
    return { getId = function() return id end, getType = function() return "TYPE_" .. id end }
end
local perkList = { makePerk("Woodwork"), makePerk("Aiming") }
PerkFactory = {
    PerkList = { size = function() return #perkList end, get = function(_, i) return perkList[i + 1] end },
    getPerkFromName = function(name)
        for _, p in ipairs(perkList) do if p.getId() == name then return p end end
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
    return self
end

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")
dofile("PZMods/PermadeathLock/42/media/lua/server/PermadeathLock_Store.lua")
dofile("PZMods/PermadeathLock/42/media/lua/server/PermadeathLock_Server.lua")

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
