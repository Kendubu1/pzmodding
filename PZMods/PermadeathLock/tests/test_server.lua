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

-- A cell holding zombies at fixed spots, so clearing can be checked by count.
local zombies = {}
local function makeZombie(x, y, z)
    local self = { _removed = false }
    self.getX = function() return x end
    self.getY = function() return y end
    self.getZ = function() return z or 0 end
    self.removeFromWorld = function() self._removed = true end
    self.removeFromSquare = function() end
    return self
end

-- Grid squares, keyed "x,y,z", each able to hold dead bodies and receive items
-- dropped on the floor.
local squares = {}

local function squareKey(x, y, z) return x .. "," .. y .. "," .. (z or 0) end

--- A corpse with a container of items.
local function makeBody(isZombie, itemCount)
    local items = {}
    for i = 1, (itemCount or 0) do items[i] = { name = "item" .. i } end
    local self = { _removed = false, _items = items }
    self.isZombie = function() return isZombie == true end
    self.removeFromWorld = function() self._removed = true end
    self.removeFromSquare = function() end
    self.getContainer = function()
        return {
            getItems = function()
                return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
            end,
            clear = function() for i = #items, 1, -1 do items[i] = nil end end,
        }
    end
    return self
end

--- Put a body on a square, creating the square if needed.
local function placeBody(x, y, z, body)
    local key = squareKey(x, y, z)
    local square = squares[key]
    if square == nil then
        local bodies, dropped = {}, {}
        square = {
            _bodies = bodies,
            _dropped = dropped,
            getDeadBodys = function()
                local live = {}
                for _, b in ipairs(bodies) do
                    if not b._removed then live[#live + 1] = b end
                end
                return { size = function() return #live end, get = function(_, i) return live[i + 1] end }
            end,
            AddWorldInventoryItem = function(_, item) dropped[#dropped + 1] = item end,
        }
        squares[key] = square
    end
    table.insert(square._bodies, body)
    return square
end

function getCell()
    return {
        getZombieList = function()
            local alive = {}
            for _, z in ipairs(zombies) do
                if not z._removed then alive[#alive + 1] = z end
            end
            return {
                size = function() return #alive end,
                get = function(_, i) return alive[i + 1] end,
            }
        end,
        getGridSquare = function(_, x, y, z) return squares[squareKey(x, y, z)] end,
    }
end

local function zombiesLeft()
    local n = 0
    for _, z in ipairs(zombies) do if not z._removed then n = n + 1 end end
    return n
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
        getX = function() return self._x end,
        getY = function() return self._y end,
        getZ = function() return self._z end,
        teleportTo = function(_, x, y, z) self._x, self._y, self._z = x, y, z; self._teleported = true end,
        getBodyDamage = function()
            return { RestoreToFullHealth = function() self._healed = true end }
        end,
        getDescriptor = function()
            return {
                getForename = function() return self._forename end,
                getSurname = function() return self._surname end,
                setForename = function(_, v) self._forename = v end,
                setSurname = function(_, v) self._surname = v end,
            }
        end,
        getHumanVisual = function()
            return {
                getLastStandString = function() return self._look end,
                loadLastStandString = function(_, s) self._look = s; return true end,
            }
        end,
        resetModelNextFrame = function() self._modelReset = true end,
    }
    self._forename = opts.forename or "Nobody"
    self._surname = opts.surname or "Nameless"
    -- Deliberately contains a tab: the real blob is opaque and the file format
    -- is tab-separated, so escaping has to survive a round trip.
    self._look = opts.look or "hair=3\tskin=1"
    self._modelReset = false
    self._x = opts.x or 100
    self._y = opts.y or 200
    self._z = opts.z or 0
    self._teleported = false
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
local onTick = handlers["OnTick"][1]

--- Run the tick handler enough times for any queued teleport to fire.
--- Comfortably past the mod's delay, so raising that does not silently break
--- these checks into passing for the wrong reason.
local function runTicks(n)
    for _ = 1, (n or 200) do onTick() end
end

--- Capture the args of the last server command of a given name.
local function lastArgsOf(command)
    for i = #sent, 1, -1 do
        if sent[i].command == command then return sent[i].args end
    end
end

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
    files, sent, online, squares = {}, {}, {}, {}
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
io.write("\n-- returning to the body --\n")

reset()
zombies = {}
local owen = makePlayer("Owen", { levels = { TYPE_Aiming = 3 }, dead = true, x = 500, y = 600, z = 0 })
online = { owen }
sweep()
check("death records where it happened", Store.get("Owen").x, 500)
check("and the y", Store.get("Owen").y, 600)

-- zombies near the body, and one far away that must survive
zombies = { makeZombie(502, 601), makeZombie(505, 604), makeZombie(900, 900) }

local revived = Store.revive("Owen", true)
check("revive at body sets the flag", revived.atBody, true)

local owenNew = makePlayer("Owen", { x = 1, y = 1 })
online = { owenNew }
sweep()                       -- restore applies, teleport is queued
check("teleport does not fire in the same frame", owenNew._teleported, false)
runTicks()
check("teleported to the body", owenNew._x, 500)
check("nearby zombies cleared", zombiesLeft(), 1)

-- a plain revive leaves them wherever they spawned
reset()
zombies = {}
local pia = makePlayer("Pia", { dead = true, x = 300, y = 400 })
online = { pia }
sweep()
Store.revive("Pia", false)
local piaNew = makePlayer("Pia", { x = 7, y = 8 })
online = { piaNew }
sweep()
runTicks()
check("plain revive does not teleport", piaNew._teleported, false)
check("plain revive leaves them put", piaNew._x, 7)

-- a record with no coordinates cannot go to the body
reset()
Store.addManual("Quinn", "added by hand")
local quinnRecord = Store.revive("Quinn", true)
check("no coordinates means no atBody", quinnRecord.atBody, false)
check("hasBody is false without coordinates", Store.hasBody(Store.get("Quinn")), false)

-- clearing is skippable
reset()
zombies = { makeZombie(501, 601) }
SandboxVars.PermadeathLock.ClearZombiesRadius = 0
local rex = makePlayer("Rex", { dead = true, x = 500, y = 600 })
online = { rex }
sweep()
Store.revive("Rex", true)
local rexNew = makePlayer("Rex", {})
online = { rexNew }
sweep()
runTicks()
check("radius 0 clears nothing", zombiesLeft(), 1)
check("but still teleports", rexNew._x, 500)
SandboxVars.PermadeathLock.ClearZombiesRadius = 15

--------------------------------------------------------------------------------
io.write("\n-- coming back as the same person --\n")

reset()
local tom = makePlayer("Tom", {
    dead = true, x = 700, y = 800,
    forename = "John", surname = "Smith", look = "hair=7\tskin=2",
})
online = { tom }
sweep()
check("name captured at death", Store.get("Tom").forename, "John")
check("surname captured", Store.get("Tom").surname, "Smith")
check("appearance captured", Store.get("Tom").look, "hair=7\tskin=2")

-- the appearance blob contains a tab; the file is tab separated
Store.load()
check("appearance survives the file round trip", Store.get("Tom").look, "hair=7\tskin=2")
check("name survives the file round trip", Store.get("Tom").forename, "John")

Store.revive("Tom", false)
local tomNew = makePlayer("Tom", { forename = "Someone", surname = "Else", look = "blank" })
online = { tomNew }
sweep()
check("new character takes the old name", tomNew._forename, "John")
check("and the old surname", tomNew._surname, "Smith")
check("and the old face", tomNew._look, "hair=7\tskin=2")
check("model redrawn", tomNew._modelReset, true)

-- identity restore can be turned off
reset()
SandboxVars.PermadeathLock.RestoreIdentity = false
local una = makePlayer("Una", { dead = true, forename = "Old", look = "oldface" })
online = { una }
sweep()
Store.revive("Una", false)
local unaNew = makePlayer("Una", { forename = "New", look = "newface" })
online = { unaNew }
sweep()
check("identity left alone when disabled", unaNew._forename, "New")
check("face left alone when disabled", unaNew._look, "newface")
SandboxVars.PermadeathLock.RestoreIdentity = true

--------------------------------------------------------------------------------
io.write("\n-- clearing your own body --\n")

reset()
zombies = {}
local vic = makePlayer("Vic", { dead = true, x = 900, y = 950 })
online = { vic }
sweep()
local corpse = makeBody(false, 3)
local square = placeBody(900, 950, 0, corpse)
local zombieCorpse = makeBody(true, 1)
placeBody(900, 950, 0, zombieCorpse)

Store.revive("Vic", true)
local vicNew = makePlayer("Vic", {})
online = { vicNew }
sweep()
runTicks()
check("own corpse removed", corpse._removed, true)
check("zombie corpse left alone", zombieCorpse._removed, false)
check("its belongings dropped on the floor", #square._dropped, 3)
check("and the body emptied", #corpse._items, 0)

-- leaving the corpse is a choice
reset()
SandboxVars.PermadeathLock.RemoveCorpseOnReturn = false
local wes = makePlayer("Wes", { dead = true, x = 10, y = 10 })
online = { wes }
sweep()
local wesCorpse = makeBody(false, 2)
placeBody(10, 10, 0, wesCorpse)
Store.revive("Wes", true)
local wesNew = makePlayer("Wes", {})
online = { wesNew }
sweep()
runTicks()
check("corpse kept when disabled", wesCorpse._removed, false)
check("belongings stay on it", #wesCorpse._items, 2)
SandboxVars.PermadeathLock.RemoveCorpseOnReturn = true

--------------------------------------------------------------------------------
io.write("\n-- admin panel data --\n")

reset()
local sara = makePlayer("Sara", { levels = { TYPE_Aiming = 2, TYPE_Woodwork = 1 }, dead = true, x = 10, y = 20 })
online = { sara }
sweep()
sent = {}
onClientCommand(MODULE, "admin", admin, { sub = "listData" })
local data = lastArgsOf("listData")
check("listData answers an admin", data ~= nil, true)
check("one row per record", #data.rows, 1)
check("row names the player", data.rows[1].username, "Sara")
check("row counts skills", data.rows[1].skills, 2)
check("row knows the body is findable", data.rows[1].hasBody, true)
check("row reports locked", data.rows[1].locked, true)
check("payload carries the version", data.version, PermadeathLock.VERSION)

sent = {}
onClientCommand(MODULE, "admin", makePlayer("Randomer", {}), { sub = "listData" })
check("listData refused to a non-admin", lastArgsOf("listData"), nil)

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
