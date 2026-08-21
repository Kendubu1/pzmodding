-- The screen overlay, and the rule that matters most about it: it must never
-- take the player's mouse away.
--
-- A full screen ISUIElement sitting in the UI manager swallows every mouse event
-- behind it. The mod used to add one the moment you spawned and only afterwards
-- try to make it click-through, so on any build without that call the whole
-- game lost right-click - doors, corpses, inventory, everything.
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
isTrue("and it was made click-through first", stubs.ui.onScreen == 1)

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
-- the build that cannot do it at all
--------------------------------------------------------------------------------

-- The regression. On a build with no setConsumeMouseEvents the overlay must be
-- abandoned, not added anyway: no visuals is a disappointment, no right-click
-- is a broken game.
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
check("a build without the call never puts it on screen", fresh.ui.onScreen, 0)

-- And it does not keep trying every frame for the rest of the session.
receiveAgain("zones", { zones = { { x = 10500, y = 9500, hazeR = 300, hazeUntil = 72, hazeHours = 72 } } })
for _ = 1, 200 do tickAgain() end
check("and it gives up rather than retrying forever", fresh.ui.onScreen, 0)

stubs.finish("test_client")
