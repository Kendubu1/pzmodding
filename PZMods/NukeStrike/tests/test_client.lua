-- The client half, and the one rule it has: it must never put anything on the
-- screen.
--
-- There used to be a full screen overlay drawing fog, a flash and a countdown,
-- and it cost the player their right-click for as long as the fog was up. An
-- element's SIZE is its hit box and the UI manager hands a click to whatever
-- element is under the cursor, so a full screen element swallows every click on
-- the world behind it. setConsumeMouseEvents(false) is supposed to prevent that
-- and does not - it does not even fail, it succeeds and the element carries on
-- eating clicks.
--
-- Shrinking it to one pixel would have worked. Deleting it cannot fail, and a
-- cosmetic tint was never worth a mouse. So this test holds the line: whatever
-- happens, nothing is added to the UI manager.
--
--     lua5.1 PZMods/NukeStrike/tests/test_client.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")
stubs.install({ server = false, client = true, coop = false })

local said = {}
stubs.player = {
    getX = function() return 10500 end,
    getY = function() return 9500 end,
    getCurrentSquare = function() return nil end,
    Say = function(_, text) said[#said + 1] = text end,
}

local halos = {}
HaloTextHelper = {
    addTextWithArrow = function(_, text) halos[#halos + 1] = text end,
    getColorRed = function() return 0 end,
}

local played = {}
function getSoundManager()
    return {
        PlayWorldSound = function() return nil end,
        PlaySound = function(_, name) played[#played + 1] = name end,
    }
end

function sendClientCommand() end

dofile("PZMods/NukeStrike/42/media/lua/shared/NukeStrike_Shared.lua")
dofile("PZMods/NukeStrike/42/media/lua/client/NukeStrike_Client.lua")

local NS = NukeStrike
local check, isTrue = stubs.check, stubs.checkTrue

local receive = NS.localReceive
local tick = stubs.registered["OnTick"][1]

local function ticks(n)
    for _ = 1, n do tick() end
end

--------------------------------------------------------------------------------
-- nothing is ever drawn
--------------------------------------------------------------------------------

check("nothing on screen at load", stubs.ui.onScreen, 0)

receive("detonate", { x = 10500, y = 9500, r = 200, hazeR = 300 })
ticks(60)
check("a detonation on top of you draws nothing", stubs.ui.onScreen, 0)

receive("warn", { x = 10500, y = 9500, r = 200, seconds = 30 })
ticks(60)
check("an inbound strike draws nothing", stubs.ui.onScreen, 0)

for _ = 1, 20 do
    receive("hazeHit", { strength = 1 })
    ticks(60)
end
check("standing in the fallout draws nothing", stubs.ui.onScreen, 0)

check("and no overlay class is left behind", rawget(_G, "NukeStrikeOverlay"), nil)

--------------------------------------------------------------------------------
-- what it does instead
--------------------------------------------------------------------------------

-- The bang lags the light in proportion to distance, so a strike a long way off
-- is not heard on the frame it lands.
played = {}
receive("detonate", { x = 10500, y = 9500, r = 200, hazeR = 300 })
tick()
check("a strike on top of you is heard at once", #played, 1)

played = {}
receive("detonate", { x = 10500 + 400, y = 9500, r = 200, hazeR = 300 })
tick()
check("one four hundred tiles away is not", #played, 0)
ticks(8 * 60)
check("but it arrives", #played, 1)
check("as a rumble, not a crack", played[1], NS.SOUND_RUMBLE)

played = {}
receive("detonate", { x = 40000, y = 40000, r = 200, hazeR = 300 })
ticks(8 * 60)
check("one on the far side of the map is never heard", #played, 0)

-- Fallout speaks through the character, not the screen.
said, halos = {}, {}
receive("hazeHit", { strength = 1 })
isTrue("breathing it makes you cough", #said > 0)
isTrue("and says so over your head", #halos > 0)

-- And does not nag on every message.
said = {}
for _ = 1, 10 do receive("hazeHit", { strength = 1 }) end
check("but not once per message", #said, 0)

ticks(31 * 60)
said = {}
receive("hazeHit", { strength = 1 })
isTrue("it comes back after a while", #said > 0)

--------------------------------------------------------------------------------
-- chat still works
--------------------------------------------------------------------------------

local messages = {}
function processGeneralMessage(text) messages[#messages + 1] = text end

receive("message", { text = "A nuclear device has detonated." })
check("server messages reach the chat", #messages, 1)

receive("message", { text = "" })
check("and empty ones do not", #messages, 1)

stubs.finish("test_client")
