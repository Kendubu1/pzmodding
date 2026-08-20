-- The server's decision making: who is allowed to call a strike, where it lands,
-- what the die does, and what the fallout costs you.
--
--     lua5.1 PZMods/NukeStrike/tests/test_server.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")

-- A dedicated server: the authoritative half is live and there is no local
-- player, so every message goes over the wire and can be captured.
stubs.install({ server = true, client = false, coop = false })

--------------------------------------------------------------------------------
-- a world to run against
--------------------------------------------------------------------------------

--- Wrap a Lua array in the size()/get() shape the game's Java lists have.
local function javaList(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
    }
end

--- One item of clothing.
local function garment(fullType)
    local item = {}
    function item:getFullType() return fullType end
    function item:hasTag() return false end
    return { getItem = function() return item end }
end

local function makePlayer(name, x, y, admin, worn)
    local player = { damage = 0, sickness = 0, endurance = 1.0 }

    function player:getUsername() return name end
    function player:getX() return x end
    function player:getY() return y end
    function player:getZ() return 0 end
    function player:isAccessLevel(level) return admin == true and level == "admin" end
    function player:getWornItems() return javaList(worn or {}) end

    function player:getBodyDamage()
        return {
            getBodyPart = function()
                return { AddDamage = function(_, amount) player.damage = player.damage + amount end }
            end,
            getFoodSicknessLevel = function() return player.sickness end,
            setFoodSicknessLevel = function(_, value) player.sickness = value end,
        }
    end

    function player:getStats()
        return {
            getEndurance = function() return player.endurance end,
            setEndurance = function(_, value) player.endurance = value end,
        }
    end

    return player
end

local admin = makePlayer("kendubu1", 10500, 9500, true)
local grunt = makePlayer("Bob", 11000, 9500, false)
local masked = makePlayer("Masked", 10500, 9500, false, { garment("Base.GasMask") })
local suited = makePlayer("Suited", 10500, 9500, false,
    { garment("Base.Hazmat_Suit"), garment("Base.GasMask") })

local roster = { admin, grunt, masked, suited }
function getOnlinePlayers() return javaList(roster) end

--------------------------------------------------------------------------------
-- capture what the server says
--------------------------------------------------------------------------------

local sent = {}

--- Both shapes of the call: broadcast (module, command, args) and targeted
--- (player, module, command, args).
function sendServerCommand(a, b, c, d)
    if type(a) == "string" then
        sent[#sent + 1] = { to = nil, command = b, args = c }
    else
        sent[#sent + 1] = { to = a, command = c, args = d }
    end
end

local function lastOf(command)
    for i = #sent, 1, -1 do
        if sent[i].command == command then return sent[i] end
    end
    return nil
end

--- Whether any chat line the server sent contains this text.
local function saidAnything(text)
    for _, message in ipairs(sent) do
        if message.command == "message" and message.args ~= nil
            and string.find(message.args.text or "", text, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function countOf(command)
    local n = 0
    for _, message in ipairs(sent) do
        if message.command == command then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- load
--------------------------------------------------------------------------------

local base = "PZMods/NukeStrike/42/media/lua/"
dofile(base .. "shared/NukeStrike_Shared.lua")
dofile(base .. "server/NukeStrike_Blast.lua")
dofile(base .. "server/NukeStrike_Server.lua")
dofile(base .. "server/NukeStrike_Zones.lua")

local NS = NukeStrike
local Server, Zones = NS.Server, NS.Zones
local check, near, isTrue = stubs.check, stubs.checkNear, stubs.checkTrue

local sandbox = SandboxVars.NukeStrike
sandbox.Enabled = true
sandbox.AdminOnly = true
sandbox.WarningSeconds = 0
sandbox.BlastRadius = 200
sandbox.HazeHours = 72
sandbox.HazeRadiusPercent = 150
sandbox.HazeDamage = 6.0
sandbox.AnnounceGlobally = true

--- Run every handler hooked to an event.
local function fireEvent(name, ...)
    for _, fn in ipairs(stubs.registered[name] or {}) do fn(...) end
end

--- Type a command, as the client would forward it.
local function typed(player, line)
    local intent = NS.parseCommand(NS.words(line))
    Server.handle(player, intent.sub, intent)
    return intent
end

--------------------------------------------------------------------------------
-- who may call a strike
--------------------------------------------------------------------------------

typed(grunt, "10500 9500")
check("a non-admin cannot call a strike", Zones.count(), 0)
isTrue("and is told why", string.find(lastOf("message").args.text, "admins", 1, true) ~= nil)

sandbox.AdminOnly = false
typed(grunt, "12000 9000")
check("unless admin-only is switched off", Zones.count(), 1)
sandbox.AdminOnly = true
Zones.clear()

--------------------------------------------------------------------------------
-- targeting
--------------------------------------------------------------------------------

typed(admin, "10500 9500")
check("a coordinate strike lands", Zones.count(), 1)
check("at the coordinate given", lastOf("detonate").args.x, 10500)
check("with the sandbox radius", lastOf("detonate").args.r, 200)
check("and a haze half again as wide", lastOf("detonate").args.hazeR, 300)
Zones.clear()

typed(admin, "here")
check("'here' lands on the caller", lastOf("detonate").args.x, 10500)
Zones.clear()

typed(admin, "player Bob")
check("a player strike lands on that player", lastOf("detonate").args.x, 11000)
Zones.clear()

typed(admin, "player Nobody")
check("an unknown player is not a strike", Zones.count(), 0)
isTrue("and says so", string.find(lastOf("message").args.text, "Nobody", 1, true) ~= nil)

typed(admin, "10500 9500 60")
check("a radius override is honoured", lastOf("detonate").args.r, 60)
Zones.clear()

typed(admin, "99999 99999")
check("off the map is refused", Zones.count(), 0)
isTrue("and says so", string.find(lastOf("message").args.text, "not on the map", 1, true) ~= nil)

sandbox.Enabled = false
typed(admin, "10500 9500")
check("a disabled mod refuses to fire", Zones.count(), 0)
sandbox.Enabled = true

--------------------------------------------------------------------------------
-- the die
--------------------------------------------------------------------------------

local realRoll = NS.rollDie

sent = {}
NS.rollDie = function() return 3 end
typed(admin, "roll 10500 9500")
check("a three keeps the bomb in the bay", Zones.count(), 0)
isTrue("and the roll is announced", saidAnything("a 3"))

sent = {}
NS.rollDie = function() return 6 end
typed(admin, "roll 10500 9500")
check("a six drops it", Zones.count(), 1)
isTrue("and the six is announced", saidAnything("A six"))

NS.rollDie = realRoll
Zones.clear()

--------------------------------------------------------------------------------
-- the countdown
--------------------------------------------------------------------------------

local clock = 1000000
NS.realMillis = function() return clock end

sandbox.WarningSeconds = 30
typed(admin, "10500 9500")

check("the sirens go first", countOf("warn"), 1)
check("and nothing has landed yet", Zones.count(), 0)

clock = clock + 29000
fireEvent("OnTick")
check("still nothing at 29 seconds", Zones.count(), 0)

clock = clock + 2000
fireEvent("OnTick")
check("it lands when the countdown runs out", Zones.count(), 1)
Zones.clear()

-- Aborting takes it back.
typed(admin, "10500 9500")
typed(admin, "abort")
clock = clock + 60000
fireEvent("OnTick")
check("an aborted strike never lands", Zones.count(), 0)
isTrue("and the abort is announced",
    string.find(lastOf("message").args.text, "aborted", 1, true) ~= nil)

-- 'now' skips the sirens entirely.
typed(admin, "now 10500 9500")
check("'now' lands at once", Zones.count(), 1)
Zones.clear()

sandbox.WarningSeconds = 0

--------------------------------------------------------------------------------
-- the fallout
--------------------------------------------------------------------------------

typed(admin, "10500 9500")

fireEvent("EveryTenMinutes")

near("standing on it costs you", admin.damage, 6.0, 0.001)
check("a mask halves it", masked.damage, 3.0)
near("a hazmat suit and a mask leave a little through", suited.damage, 0.3, 0.001)
check("out at 1500 tiles there is nothing to breathe", grunt.damage, 0)
isTrue("sickness rises too", admin.sickness > 0)
isTrue("endurance drops", admin.endurance < 1.0)

-- Three days on, the air is clear.
admin.damage = 0
stubs.hours = 80
fireEvent("EveryTenMinutes")
check("the haze expires", admin.damage, 0)
stubs.hours = 0

--------------------------------------------------------------------------------
-- status
--------------------------------------------------------------------------------

sent = {}
typed(grunt, "status")
isTrue("anyone may read the status", countOf("message") > 0)

sent = {}
Zones.clear()
typed(admin, "status")
isTrue("an empty board says so",
    string.find(lastOf("message").args.text, "No strikes", 1, true) ~= nil)

stubs.finish("test_server")
