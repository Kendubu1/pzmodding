-- The screen overlay, and the rule that matters most about it: it must never
-- take the player's mouse away.
--
-- An element's SIZE is its hit box, and the UI manager hands a click to whatever
-- element is under the cursor. A full screen element therefore swallows every
-- click on the world behind it. setConsumeMouseEvents(false) is supposed to
-- prevent that and does not - it succeeds and the element goes on eating clicks
-- anyway, which is why right-click broke only while the fog was up.
--
-- So the guarantee is the size: one pixel, in the corner. drawRect is not
-- clipped to the element's bounds, so it still paints the whole screen.
--
--     lua5.1 PZMods/NukeStrike/tests/test_client.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")
stubs.install({ server = false, client = true, coop = false })

stubs.player = {
    getX = function() return 10500 end,
    getY = function() return 9500 end,
    getCurrentSquare = function() return nil end,
    Say = function() end,
}

function sendClientCommand() end

dofile("PZMods/NukeStrike/42/media/lua/shared/NukeStrike_Shared.lua")
dofile("PZMods/NukeStrike/42/media/lua/client/NukeStrike_Client.lua")

local NS = NukeStrike
local check, isTrue = stubs.check, stubs.checkTrue

local receive = NS.localReceive
local tick = stubs.registered["OnTick"][1]
local onCreatePlayer = stubs.registered["OnCreatePlayer"][1]

local function ticks(n)
    for _ = 1, n do tick() end
end

--------------------------------------------------------------------------------
-- nothing on screen when nothing is happening
--------------------------------------------------------------------------------

check("nothing is on screen at load", stubs.ui.onScreen, 0)

onCreatePlayer(0, stubs.player)
ticks(5)
check("spawning does not put anything on screen", stubs.ui.onScreen, 0)

-- The zone list arriving is not by itself a reason to draw: the clouds may all
-- be on the far side of the map.
receive("zones", { zones = { { x = 1, y = 1, hazeR = 50, hazeUntil = 72, hazeHours = 72 } } })
ticks(60)
check("a distant cloud draws nothing", stubs.ui.onScreen, 0)

--------------------------------------------------------------------------------
-- on screen only while there is something to draw
--------------------------------------------------------------------------------

receive("detonate", { x = 10500, y = 9500, r = 200, hazeR = 300 })
tick()
check("a detonation puts it on screen", stubs.ui.onScreen, 1)

-- THE regression. Everything else in this file is secondary to this line: an
-- element wider than a pixel is an element that can take the mouse away.
check("and it is one pixel wide, not screen wide", stubs.ui.last.width, 1)
check("and one pixel tall", stubs.ui.last.height, 1)

-- The flash decays over about a second, and then it should leave.
ticks(200)
check("and it leaves when the flash has faded", stubs.ui.onScreen, 0)

-- A countdown brings it back, and takes it away again when it runs out.
receive("warn", { x = 10500, y = 9500, r = 200, seconds = 30 })
tick()
check("an inbound strike puts it back", stubs.ui.onScreen, 1)
ticks(120)
check("and it stays up for the whole countdown", stubs.ui.onScreen, 1)

stubs.millis = stubs.millis + 31000
ticks(5)
check("and it goes when the countdown is done", stubs.ui.onScreen, 0)

-- Standing in fallout keeps it up for as long as the fallout lasts.
receive("zones", { zones = { { x = 10500, y = 9500, hazeR = 300, hazeUntil = 72, hazeHours = 72 } } })
ticks(30)
check("standing in the haze puts it up", stubs.ui.onScreen, 1)
ticks(300)
check("and it stays up while you are in it", stubs.ui.onScreen, 1)

-- Walking out of the cloud clears it.
receive("zones", { zones = {} })
ticks(200)
check("walking out of it clears the screen", stubs.ui.onScreen, 0)

--------------------------------------------------------------------------------
-- the build without setConsumeMouseEvents
--
-- This used to mean giving up on the visuals entirely, because the overlay was
-- full screen and that call was the only thing standing between it and the
-- player's mouse. Now that the element is a single pixel, the call is belt and
-- braces and its absence costs nothing: the fog is still drawn, and the mouse is
-- still fine.
--------------------------------------------------------------------------------

local fresh = dofile("PZMods/NukeStrike/tests/stubs.lua")
fresh.install({ server = false, client = true, coop = false })
fresh.consumeMouseEventsWorks = false
fresh.player = stubs.player
function sendClientCommand() end

NukeStrike = nil
dofile("PZMods/NukeStrike/42/media/lua/shared/NukeStrike_Shared.lua")
dofile("PZMods/NukeStrike/42/media/lua/client/NukeStrike_Client.lua")

local receiveAgain = NukeStrike.localReceive
local tickAgain = fresh.registered["OnTick"][1]

receiveAgain("detonate", { x = 10500, y = 9500, r = 200, hazeR = 300 })
for _ = 1, 10 do tickAgain() end

check("the fog is still drawn without that call", fresh.ui.onScreen, 1)
check("and the element is still one pixel", fresh.ui.last.width, 1)
check("in both directions", fresh.ui.last.height, 1)

stubs.finish("test_client")
