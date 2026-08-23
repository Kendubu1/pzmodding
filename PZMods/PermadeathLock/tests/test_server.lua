-- Harness: drives PermadeathLock_Server's sweep and client-command handlers
-- against stubbed Project Zomboid globals.

local files = {}
local sent = {}          -- captured sendServerCommand calls
local online = {}        -- players currently "connected"
local handlers = {}      -- captured Events.*.Add callbacks

function isServer() return true end
function isClient() return false end
local now = 1700000000
function getTimestamp() return now end
--- Advance the server's real-time clock, for the kill backstop's deadline.
local function advance(seconds) now = now + seconds end
function print(...) end

-- Kahlua, the Lua implementation Project Zomboid runs, does not provide every
-- Lua 5.1 global. `next` in particular is missing, and a call to it threw on
-- every sweep. Removing them here makes that class of mistake a failing test
-- rather than a server log full of stack traces. pairs/ipairs are unaffected:
-- Lua 5.1 implements them natively rather than through the global.
next = nil  -- silence the mod's console output

SandboxVars = { PermadeathLock = {
    Enabled = true, ExemptAdmins = true, EnforceKill = true,
    RestoreSkillsOnRevive = true,
    -- The disconnect path is the one the existing checks describe, so the
    -- default is turned off here and tested on its own below.
    KillOnSpawn = false,
} }

Events = setmetatable({}, { __index = function(t, name)
    local slot = {
        Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
        Remove = function() end,
    }
    rawset(t, name, slot)
    return slot
end })

-- REGRESSION: adding to the server's copy of a container is only half of it.
-- Without the broadcast the item exists server-side, the admin panel counts it,
-- and the player's inventory never shows it.
local broadcast = { added = 0, removed = 0 }
function sendAddItemToContainer() broadcast.added = broadcast.added + 1 end
function sendRemoveItemFromContainer() broadcast.removed = broadcast.removed + 1 end
function syncItemFields() end

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
local perkList = {
    makePerk("Woodwork", "Carpentry"),
    makePerk("Aiming", "Aiming"),
    makePerk("Fitness", "Fitness"),
}
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
    container.AddItem = function(_, fullType)
        local data = {}
        local item = {
            getModData = function() return data end,
            getFullType = function() return fullType end,
            getContainer = function() return container end,
            IsInventoryContainer = function() return false end,
            getInventory = function() error("getInventory called on a plain item") end,
        }
        items[#items + 1] = item
        return item
    end
    for _ = 1, tokens or 0 do
        local data = {}
        items[#items + 1] = {
            getModData = function() return data end,
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
        _x = opts.x or 100,
        _y = opts.y or 200,
        _z = 0,
        _levels = held,
        getUsername = function() return username end,
        getSteamID = function() return "7656119800000000" end,
        isDead = function() return self._dead end,
        isAccessLevel = function(_, level) return opts.admin == true and level == "admin" end,
        getPerkLevel = function(_, t)
            -- A restore that blows up rather than killing anyone: there is then
            -- no perk to blame, and nothing for the retry to drop.
            if opts.perkError then error("perk lookup exploded") end
            return held[t] or 0
        end,
        LevelPerk = function(_, t)
            held[t] = (held[t] or 0) + 1
            if opts.dieOnPerk == t then self._dead = true end
            if opts.dieWhenUnhealedPerk == t and not self._healed then self._dead = true end
        end,
        Kill = function() self._dead = true end,
        getX = function() return self._x end,
        getY = function() return self._y end,
        getZ = function() return self._z end,
        teleportTo = function(_, x, y, z)
            if opts.noTeleport then return end
            self._x, self._y, self._z = x, y, z
        end,
        getHumanVisual = function()
            return {
                getLastStandString = function() return opts.visual end,
                loadLastStandString = function() end,
            }
        end,
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
check("but does not touch the character", bobAgain._dead, false)

--------------------------------------------------------------------------------
io.write("\n-- revive --\n")
-- Continues the Bob thread from the section above: do not put a reset() in
-- between, or Bob has no record left to be revived from.

Store.revive("Bob")
sent = {}
local bobRevived = makePlayer("Bob", {})

-- REGRESSION: the restore used to be applied right here, inside the spawn
-- handshake. OnCreatePlayer fires while the character is still loading into the
-- world, and handing it a whole character's worth of perk levels at that
-- instant is the same unsafe moment that black-screened people when the kill
-- was done here. The handshake now only asks the client to say when it has
-- settled.
onClientCommand(MODULE, "checkStatus", bobRevived, {})
check("the handshake only asks them to settle", lastCommandTo("Bob"), "settle")
check("no skills applied mid-spawn", bobRevived._levels.TYPE_Woodwork, nil)
check("and the record is still owed", Store.get("Bob") ~= nil, true)

sent = {}
onClientCommand(MODULE, "spawnSettled", bobRevived, {})
check("settling applies the skills", bobRevived._levels.TYPE_Woodwork, 5)
check("record cleared after restore", Store.get("Bob"), nil)
check("and they are told on screen, not just in chat", lastCommandTo("Bob"), "message")

local sawNotice = false
for _, entry in ipairs(sent) do
    if entry.user == "Bob" and entry.command == "notice" then sawNotice = true end
end
check("a notice is put on their screen", sawNotice, true)

-- regression: an exempt admin must still receive a queued restore
reset()
local adminDead = makePlayer("Boss", { levels = { TYPE_Aiming = 3 } })
Store.record(adminDead, "test")          -- recorded while not exempt
Store.revive("Boss")
local adminBack = makePlayer("Boss", { admin = true })
online = { adminBack }
sweep()   -- first sweep: still could be loading, so only noted as alive
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
onClientCommand(MODULE, "spawnSettled", caraDead, {})
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
sweep()
check("restore applied", deeNew._levels.TYPE_Woodwork, 2)
deeNew._dead = true
sweep()
check("second death re-locks them", Store.isLocked("Dee"), true)

--------------------------------------------------------------------------------
io.write("\n-- a restore that kills the character --\n")

-- REGRESSION: not spending the rescue when a restore kills the character is
-- right, but leaving the lethal perk in the snapshot hands it to the next
-- character too, and the next. The player then dies on every spawn, forever,
-- which is a worse failure than losing one skill.
reset()
local zed = makePlayer("Zed", { levels = { TYPE_Aiming = 4, TYPE_Fitness = 3 } })
Store.record(zed, "test")
Store.revive("Zed")

local zedOne = makePlayer("Zed", { dieOnPerk = "TYPE_Fitness" })
online = { zedOne }
onClientCommand(MODULE, "spawnSettled", zedOne, {})
check("the restore kills the first character", zedOne._dead, true)
check("and the rescue is not spent", Store.get("Zed") ~= nil, true)
check("the perk that did it is dropped", Store.get("Zed").skills.Fitness, nil)
check("the harmless ones are kept", Store.get("Zed").skills.Aiming, 4)

local zedTwo = makePlayer("Zed", { dieOnPerk = "TYPE_Fitness" })
online = { zedTwo }
onClientCommand(MODULE, "spawnSettled", zedTwo, {})
check("the next character survives", zedTwo._dead, false)
check("and gets what was left", zedTwo._levels.TYPE_Aiming, 4)
check("the rescue is spent now", Store.get("Zed"), nil)

-- and when there is nothing to blame, it gives up rather than loop forever
reset()
local yara = makePlayer("Yara", { levels = { TYPE_Aiming = 2 } })
Store.record(yara, "test")
Store.revive("Yara")

local function yaraSpawns()
    local body = makePlayer("Yara", { perkError = true })
    online = { body }
    onClientCommand(MODULE, "spawnSettled", body, {})
    return body
end

yaraSpawns()
check("a blameless failure keeps the rescue", Store.get("Yara") ~= nil, true)
yaraSpawns()
check("and still keeps it on the second try", Store.get("Yara") ~= nil, true)
yaraSpawns()
check("but the third abandons it rather than loop forever", Store.get("Yara"), nil)

--------------------------------------------------------------------------------
io.write("\n-- the sweep waits for a character to finish loading --\n")

-- REGRESSION: deferring the restore off the spawn handshake achieved nothing
-- while the sweep still applied it the instant it saw a living character. A
-- sweep is one IN-GAME minute - two or three real seconds at the default day
-- length - so it beat the client's four-second settle signal nearly every time,
-- and the restore landed on a character that was still loading anyway.
reset()
local opal = makePlayer("Opal", { levels = { TYPE_Aiming = 5 } })
Store.record(opal, "test")
Store.revive("Opal")
local opalNew = makePlayer("Opal", {})
online = { opalNew }
sweep()
check("the first sweep does not restore", opalNew._levels.TYPE_Aiming, nil)
check("and the restore is still owed", Store.get("Opal") ~= nil, true)
sweep()
check("the second one does", opalNew._levels.TYPE_Aiming, 5)
check("and clears the record", Store.get("Opal"), nil)

--------------------------------------------------------------------------------
io.write("\n-- spending a token and coming back --\n")

-- The whole path a player actually walks: alive with a token, dead, new
-- character, skills back. Reported as "I respawn after using a fate token and
-- suddenly die, with no prompt about the token".
reset()
local nate = makePlayer("Nate", { levels = { TYPE_Woodwork = 6, TYPE_Aiming = 3 }, tokens = 1 })
online = { nate }
sweep()                                    -- seen alive, carrying it
nate._dead = true
sent = {}
sweep()                                    -- dies
check("the token is spent, not the player", Store.isLocked("Nate"), false)
check("and they are told at the moment of death", lastCommandTo("Nate"), "tokenSpent")

local nateNew = makePlayer("Nate", {})
online = { nateNew }
sent = {}
onClientCommand(MODULE, "checkStatus", nateNew, {})
check("the new character is not touched on spawn", lastCommandTo("Nate"), "settle")
check("no skills applied yet", nateNew._levels.TYPE_Woodwork, nil)
check("and nothing has killed them", nateNew._dead, false)

sent = {}
onClientCommand(MODULE, "spawnSettled", nateNew, {})
check("settling hands back the skills", nateNew._levels.TYPE_Woodwork, 6)
check("all of them", nateNew._levels.TYPE_Aiming, 3)
check("they are off the list afterwards", Store.get("Nate"), nil)
check("and still alive", nateNew._dead, false)

local toldOnScreen = false
for _, entry in ipairs(sent) do
    if entry.user == "Nate" and entry.command == "notice"
        and entry.args ~= nil and string.find(entry.args.text or "", "Fate Token") then
        toldOnScreen = true
    end
end
check("the notice names the token that paid for it", toldOnScreen, true)

--------------------------------------------------------------------------------
io.write("\n-- a restore cannot consume its own rescue --\n")

reset()
local orla = makePlayer("Orla", { levels = { TYPE_Fitness = 6 }, dead = true, tokens = 1 })
online = { orla }
sweep()

local orlaNew = makePlayer("Orla", { dieWhenUnhealedPerk = "TYPE_Fitness" })
online = { orlaNew }
sweep()
sweep()
check("physical perks are healed before restoration", orlaNew._dead, false)
check("a successful guarded restore clears the record", Store.get("Orla"), nil)

reset()
local pax = makePlayer("Pax", { levels = { TYPE_Fitness = 6 }, dead = true, tokens = 1 })
online = { pax }
sweep()

local paxNew = makePlayer("Pax", { dieOnPerk = "TYPE_Fitness" })
online = { paxNew }
sweep()
sweep()
check("the harness can reproduce a restore-time death", paxNew._dead, true)
check("a failed restore remains queued", Store.get("Pax").pendingRestore, true)
check("a failed restore never locks the saved player", Store.get("Pax").locked, false)

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
io.write("\n-- killing on spawn instead of disconnecting --\n")

reset()
SandboxVars.PermadeathLock.KillOnSpawn = true
local uma = makePlayer("Uma", { dead = true })
online = { uma }
sweep()
check("Uma is locked out", Store.isLocked("Uma"), true)

-- REGRESSION: the kill used to happen inside the spawn handshake, while the
-- character was still loading into the world. That is what left people looking
-- at a black screen they never came back from. Nothing may die here.
sent = {}
local umaNew = makePlayer("Uma", {})
online = { umaNew }
onClientCommand(MODULE, "checkStatus", umaNew, {})
check("the spawn handshake does not kill", umaNew._dead, false)
check("it tells them instead", lastCommandTo("Uma"), "blocked")
check("and says the character is forfeit", sent[#sent].args.kill, true)

-- the client finishes loading and reports in; the kill happens then, here
sent = {}
onClientCommand(MODULE, "spawnSettled", umaNew, {})
check("settling is when the character dies", umaNew._dead, true)

-- REGRESSION: the kill used to be relayed to the client, which killed itself.
-- The server then went on believing the character was alive - the admin panel
-- showed them alive and the death was never recorded. One authority for who is
-- dead, and it is this side.
local warned = false
for _, entry in ipairs(sent) do
    if entry.user == "Uma" and entry.command == "notice" then warned = true end
end
check("and they are told, on screen, that the lock did it", warned, true)

-- REGRESSION: a pardon during the client's grace period must call it off.
-- Killing anyway is a bug the player experiences as the pardon not working.
reset()
local vic = makePlayer("Vic", { dead = true })
online = { vic }
sweep()
local vicNew = makePlayer("Vic", {})
-- Its own admin: the shared one is not declared until the section below, and a
-- nil sender is dropped by the command handler, so the pardon would never run.
local graceAdmin = makePlayer("Admin", { admin = true })
online = { vicNew, graceAdmin }
onClientCommand(MODULE, "checkStatus", vicNew, {})
onClientCommand(MODULE, "admin", graceAdmin, { sub = "pardon", target = "Vic" })
check("the pardon landed", Store.get("Vic"), nil)
sent = {}
onClientCommand(MODULE, "spawnSettled", vicNew, {})
check("a pardon mid-grace calls the kill off", lastCommandTo("Vic"), nil)
check("and they stay alive", vicNew._dead, false)

-- a client that never goes through with it is killed from here, but only well
-- after the deadline
reset()
local wren = makePlayer("Wren", { dead = true })
online = { wren }
sweep()
local wrenNew = makePlayer("Wren", {})
online = { wrenNew }
sweep()
check("the sweep tells them first", wrenNew._dead, false)
advance(5)
sweep()
check("and does not kill inside the grace period", wrenNew._dead, false)
advance(20)
sweep()
check("but does once the deadline passes", wrenNew._dead, true)

-- each new character starts the count over rather than being killed instantly
local wrenAgain = makePlayer("Wren", {})
online = { wrenAgain }
sweep()
check("the next character gets its own grace", wrenAgain._dead, false)
advance(30)
sweep()
check("and is killed once that runs out too", wrenAgain._dead, true)

-- being killed by the block must not spend a Fate Token they happen to hold
local umaToken = makePlayer("Wren", { tokens = 1 })
online = { umaToken }
sweep()
advance(30)
sweep()
check("an enforcement kill does not eat a token", #umaToken._items, 1)
check("and does not unlock them", Store.isLocked("Wren"), true)
SandboxVars.PermadeathLock.KillOnSpawn = false

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
sweep()
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
io.write("\n-- the admin panel's roster feed --\n")

reset()
local sara = makePlayer("Sara", { levels = { TYPE_Woodwork = 3, TYPE_Aiming = 1 }, dead = true })
online = { sara }
sweep()

local panelAdmin = makePlayer("Admin", { admin = true })
sent = {}
onClientCommand(MODULE, "admin", panelAdmin, { sub = "listdata" })
local payload = sent[#sent]
check("listData answers an admin", payload.command, "listData")
check("the row names the player", payload.args.rows[1].username, "Sara")
check("and counts their skills", payload.args.rows[1].skills, 2)
check("and reports them locked", payload.args.rows[1].locked, true)
check("the payload carries the version", payload.args.version, PermadeathLock.VERSION)

-- the roster covers the living too, which is the point of it
local wes = makePlayer("Wes", { tokens = 2 })
online = { sara, wes, panelAdmin }
sent = {}
onClientCommand(MODULE, "admin", panelAdmin, { sub = "listdata" })
payload = sent[#sent]
local rows = {}
for _, row in ipairs(payload.args.rows) do rows[row.username] = row end
check("a player who never died is listed", rows.Wes ~= nil, true)
check("they are not on the death list", rows.Wes and rows.Wes.listed, false)
check("their tokens are counted", rows.Wes and rows.Wes.tokens, 2)
check("and they are reported online", rows.Wes and rows.Wes.online, true)
check("an exempt admin is flagged as such", rows.Admin and rows.Admin.exempt, true)
check("the dead player is still there", rows.Sara and rows.Sara.locked, true)

-- trouble sorts to the top
check("locked players come first", payload.args.rows[1].username, "Sara")

sent = {}
onClientCommand(MODULE, "admin", makePlayer("Nobody", {}), { sub = "listdata" })
check("but not a non-admin", sent[1] and sent[1].command, "message")

--------------------------------------------------------------------------------
io.write("\n-- handing out and taking back tokens --\n")

reset()
local tara = makePlayer("Tara", {})
local tokenAdmin = makePlayer("Admin", { admin = true })
online = { tara, tokenAdmin }

-- REGRESSION: the grant used to be relayed to the target's client to carry out.
-- In Build 42 the server never saw the result: the count reported to the admin
-- was 0, and - the part that actually mattered - the death check reads this
-- same inventory, so a token handed out through the panel saved nobody. Players
-- died carrying three of them and were locked out.
sent = {}
broadcast = { added = 0, removed = 0 }
onClientCommand(MODULE, "admin", tokenAdmin, { sub = "give", target = "tara" })
check("the token is really in their inventory", #tara._items, 1)
-- REGRESSION: without the broadcast the item exists here, the panel counts it,
-- and the player's own inventory never shows it.
check("and the client is told about it", broadcast.added, 1)
check("the admin is told, and gets a fresh roster", lastCommandTo("Admin"), "listData")

onClientCommand(MODULE, "admin", tokenAdmin, { sub = "give", target = "tara" })
check("a second one stacks up", #tara._items, 2)

-- and the count the admin is shown is the real one
local told = nil
for i = #sent, 1, -1 do
    if sent[i].user == "Admin" and sent[i].text ~= nil then told = sent[i].text break end
end
check("the count reported is not zero", told ~= nil and string.find(told, "carry 2") ~= nil, true)

-- the death check must honour a token handed out this way, immediately
tara._dead = true
sweep()
check("dying with a granted token does not lock them out", Store.isLocked("Tara"), false)
check("and the granted token is what was spent", #tara._items, 1)

-- taking one back
reset()
local ursa = makePlayer("Ursa", { tokens = 2 })
online = { ursa, tokenAdmin }
broadcast = { added = 0, removed = 0 }
onClientCommand(MODULE, "admin", tokenAdmin, { sub = "take", target = "Ursa" })
check("take removes one", #ursa._items, 1)
check("and that is broadcast too", broadcast.removed, 1)
onClientCommand(MODULE, "admin", tokenAdmin, { sub = "take", target = "Ursa" })
check("and then the last one", #ursa._items, 0)
sent = {}
onClientCommand(MODULE, "admin", tokenAdmin, { sub = "take", target = "Ursa" })
check("taking from empty hands is refused", lastCommandTo("Admin"), "message")

-- REGRESSION: taking the last token must not leave the death check thinking
-- they still have one from an earlier sweep.
ursa._dead = true
sweep()
check("a revoked token does not still save them", Store.isLocked("Ursa"), true)

-- a non-admin cannot hand themselves one
reset()
sent = {}
local greedy = makePlayer("Greedy", {})
online = { greedy }
onClientCommand(MODULE, "admin", greedy, { sub = "give", target = "Greedy" })
check("a non-admin is refused", lastCommandTo("Greedy"), "message")
check("and gets nothing", #greedy._items, 0)

-- an offline target is refused, not silently lost
reset()
online = { tokenAdmin }
sent = {}
onClientCommand(MODULE, "admin", tokenAdmin, { sub = "take", target = "Ghosty" })
check("offline target is refused", lastCommandTo("Admin"), "message")

--------------------------------------------------------------------------------
io.write("\n-- binding a Fate Token to a place --\n")

reset()
SandboxVars.PermadeathLock.FateBinding = true

-- binding needs a token actually in hand, whatever the menu offered
local broke = makePlayer("Broke", { tokens = 0, x = 500, y = 600 })
online = { broke }
sent = {}
onClientCommand(MODULE, "bind", broke, { x = 500, y = 600, z = 0 })
check("no token, no binding", lastCommandTo("Broke"), "message")

-- the coordinate goes on the token itself
local rob = makePlayer("Rob", { tokens = 1, x = 500, y = 600 })
online = { rob }
onClientCommand(MODULE, "bind", rob, { x = 500, y = 600, z = 0 })
check("the token carries the bind", PermadeathLock.getTokenBind(rob._items[1]) ~= nil, true)
check("at the right place", PermadeathLock.getTokenBind(rob._items[1]).x, 500)

-- die on it, come back to it
rob._dead = true
online = { rob }
sweep()
check("the token saved them", Store.isLocked("Rob"), false)
check("and the record carries the place it pointed at", Store.get("Rob").bind.x, 500)

local robNew = makePlayer("Rob", { x = 1, y = 1 })
online = { robNew }
onClientCommand(MODULE, "spawnSettled", robNew, {})
check("they wake at the bound spot", math.floor(robNew._x), 500)

-- a second bind takes an UNBOUND token rather than moving the one already placed
reset()
local pair = makePlayer("Pair", { tokens = 2, x = 10, y = 20 })
online = { pair }
onClientCommand(MODULE, "bind", pair, { x = 10, y = 20, z = 0 })
onClientCommand(MODULE, "bind", pair, { x = 30, y = 40, z = 0 })
check("the first token keeps its place", PermadeathLock.getTokenBind(pair._items[1]).x, 10)
check("and the second gets its own", PermadeathLock.getTokenBind(pair._items[2]).x, 30)

-- an admin revive has no token and so nothing to read
reset()
local sal = makePlayer("Sal", { x = 700, y = 800 })
Store.record(sal, "test")
Store.revive("Sal")
local salNew = makePlayer("Sal", { x = 5, y = 5 })
online = { salNew }
onClientCommand(MODULE, "spawnSettled", salNew, {})
check("a revive does not move anyone", math.floor(salNew._x), 5)

-- a spot that cannot be reached leaves them where the game put them
reset()
local tim = makePlayer("Tim", { tokens = 1, x = 900, y = 900 })
online = { tim }
onClientCommand(MODULE, "bind", tim, { x = 900, y = 900, z = 0 })
tim._dead = true
sweep()
local timNew = makePlayer("Tim", { x = 5, y = 5, noTeleport = true })
online = { timNew }
sent = {}
onClientCommand(MODULE, "spawnSettled", timNew, {})
check("an unreachable bind strands nobody", math.floor(timNew._x), 5)
check("and says so rather than failing silently", lastCommandTo("Tim"), "message")

-- the bind survives being written out and read back
reset()
local van = makePlayer("Van", { tokens = 1, x = 111, y = 222 })
online = { van }
onClientCommand(MODULE, "bind", van, { x = 111, y = 222, z = 0 })
van._dead = true
sweep()
Store.load()
check("the bind survives a reload", Store.get("Van").bind.y, 222)

-- switched off, binding is refused
reset()
SandboxVars.PermadeathLock.FateBinding = false
local urs = makePlayer("Urs", { tokens = 1, x = 300, y = 300 })
online = { urs }
onClientCommand(MODULE, "bind", urs, { x = 300, y = 300, z = 0 })
check("binding switched off is refused", PermadeathLock.getTokenBind(urs._items[1]), nil)
SandboxVars.PermadeathLock.FateBinding = true

--------------------------------------------------------------------------------
io.write("\n-- what the mod knows about one player --\n")

reset()
local dumpAdmin = makePlayer("Admin", { admin = true })
local pia = makePlayer("Pia", { tokens = 2 })
online = { pia, dumpAdmin }
sent = {}
onClientCommand(MODULE, "admin", dumpAdmin, { sub = "status", target = "Pia" })

local dump = ""
for _, entry in ipairs(sent) do
    if entry.user == "Admin" and entry.text ~= nil then dump = dump .. entry.text .. "\n" end
end
check("it names them", string.find(dump, "Pia") ~= nil, true)
check("it reports their tokens", string.find(dump, "carrying 2 Fate Token") ~= nil, true)
check("it says they are not listed", string.find(dump, "not on the death list") ~= nil, true)
check("and it prints the settings that decide behaviour",
    string.find(dump, "ExemptAdmins=") ~= nil and string.find(dump, "KillOnSpawn=") ~= nil, true)
-- Leaving one out is how someone ends up hunting a bug that is a switch.
check("including the skill restore switch", string.find(dump, "RestoreSkills=") ~= nil, true)
check("and which Lua state answered", string.find(dump, "isCoopHost=") ~= nil, true)

-- the plain status is unchanged when no target is given
sent = {}
onClientCommand(MODULE, "admin", dumpAdmin, { sub = "status" })
check("bare status still reports the lock", string.find(sent[1].text or "", "Permadeath Lock") ~= nil, true)

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
