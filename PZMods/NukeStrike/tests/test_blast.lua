-- The blast engine against a toy world: does the sweep finish, does it level
-- what it should and leave alone what it should not, and does ground that was
-- not loaded at the time get levelled when it finally arrives.
--
--     lua5.1 PZMods/NukeStrike/tests/test_blast.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")
stubs.install({ server = false, client = false, coop = false })

local function javaList(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
        items = items,
    }
end

--------------------------------------------------------------------------------
-- a toy world
--------------------------------------------------------------------------------

local world = {}      -- ["x,y,z"] = square
local burned = {}     -- ["x,y"] = true
local ignited = {}    -- ["x,y"] = true

local function makeSquare(x, y, z)
    local square = { x = x, y = y, z = z, killed = 0 }

    local floor = { name = "floor" }
    local structure = javaList({ floor, { name = "wall" }, { name = "couch" } })
    local fittings = javaList({ { name = "door" }, { name = "window" } })

    local zombie = {
        kind = "zombie",
        removeFromWorld = function() square.killed = square.killed + 1 end,
        removeFromSquare = function() end,
        Kill = function() square.killed = square.killed + 1 end,
    }
    local movers = javaList({ zombie })

    function square:getX() return x end
    function square:getY() return y end
    function square:getZ() return z end
    function square:getObjects() return structure end
    function square:getSpecialObjects() return fittings end
    function square:getMovingObjects() return movers end
    function square:getFloor() return floor end
    function square:removeAllWorldObjects() end
    function square:StartFire() ignited[x .. "," .. y] = true end
    function square:Burn() burned[x .. "," .. y] = true end

    local function drop(list, obj)
        for i, held in ipairs(list.items) do
            if held == obj then table.remove(list.items, i) return true end
        end
        return false
    end

    function square:transmitRemoveItemFromSquare(obj)
        if not drop(structure, obj) then drop(fittings, obj) end
    end

    square.structure = structure
    square.fittings = fittings
    return square
end

local function place(x, y, z)
    local square = makeSquare(x, y, z)
    world[x .. "," .. y .. "," .. z] = square
    return square
end

-- A sixteen by sixteen patch of loaded ground. Everything outside it is "not in
-- memory", which is the normal state of most of the map.
for x = 100, 115 do
    for y = 100, 115 do
        place(x, y, 0)
    end
end

--------------------------------------------------------------------------------
-- a car park
--------------------------------------------------------------------------------

local parked = {}

--- A car. `broken` makes getPartCount raise, standing in for the one awkward
--- vehicle that a shared error guard used to let take the whole feature down.
local function makeVehicle(x, y, broken, unremovable)
    local vehicle = { x = x, y = y, removed = false, ruined = 0 }

    function vehicle:getX() return x end
    function vehicle:getY() return y end
    function vehicle:getSquare() return world[x .. "," .. y .. ",0"] end

    function vehicle:getPartCount()
        if broken then error("no parts on this build") end
        return 3
    end

    function vehicle:getPartByIndex()
        return { setCondition = function() vehicle.ruined = vehicle.ruined + 1 end }
    end

    function vehicle:permanentlyRemove()
        if unremovable then error("permanentlyRemove is not a thing here") end
        vehicle.removed = true
        for i, held in ipairs(parked) do
            if held == vehicle then table.remove(parked, i) return end
        end
    end

    parked[#parked + 1] = vehicle
    return vehicle
end

stubs.cell = {
    getGridSquare = function(_, x, y, z) return world[x .. "," .. y .. "," .. z] end,
    getVehicles = function() return javaList(parked) end,
}

function instanceof(obj, class)
    return class == "IsoZombie" and type(obj) == "table" and obj.kind == "zombie"
end

--------------------------------------------------------------------------------
-- load
--------------------------------------------------------------------------------

local base = "PZMods/NukeStrike/42/media/lua/"
dofile(base .. "shared/NukeStrike_Shared.lua")
dofile(base .. "server/NukeStrike_Blast.lua")
dofile(base .. "server/NukeStrike_Zones.lua")

local NS = NukeStrike
local Blast, Zones = NS.Blast, NS.Zones
local check, isTrue = stubs.check, stubs.checkTrue

local sandbox = SandboxVars.NukeStrike
sandbox.MaxFloors = 1
sandbox.FlattenPercent = 100   -- the whole radius is inside the fireball
sandbox.HeavyPercent = 100
sandbox.MaxFires = 40
sandbox.FireChance = 55
-- Deliberately small, so the sweep has to survive being interrupted and resumed
-- across many ticks rather than finishing in one.
sandbox.SquaresPerTick = 20

--- Turn the crank until the queue is empty, and fail rather than hang if it
--- never is.
---@return integer ticks taken
local function runToCompletion()
    local ticks = 0
    while #Blast.jobs > 0 do
        ticks = ticks + 1
        if ticks > 5000 then
            io.write("FAIL blast queue never drains\n")
            os.exit(1)
        end
        for _, fn in ipairs(stubs.registered["OnTick"] or {}) do fn() end
    end
    return ticks
end

--------------------------------------------------------------------------------
-- the sweep
--------------------------------------------------------------------------------

local zone = Zones.add(105, 105, 6, 9, 72, 0, "test")
Blast.detonate(zone, nil)

isTrue("the strike queues work", #Blast.jobs > 0)
local ticks = runToCompletion()
isTrue("the sweep takes more than one tick at this budget", ticks > 1)
check("and then the queue is empty", #Blast.jobs, 0)

local centre = world["105,105,0"]
check("ground zero keeps its floor", #centre.structure.items, 1)
check("and it is the floor", centre.structure.items[1].name, "floor")
check("the doors and windows are gone", #centre.fittings.items, 0)
isTrue("and the zombie standing there is not standing there", centre.killed > 0)

local edge = world["111,105,0"]
check("the last square inside the radius is levelled", #edge.structure.items, 1)

local outside = world["113,105,0"]
check("a square outside the radius keeps its walls", #outside.structure.items, 3)
check("and its fittings", #outside.fittings.items, 2)
check("and its zombie", outside.killed, 0)

isTrue("ground zero is scorched", burned["105,105"] == true)

local fires = 0
for _ in pairs(ignited) do fires = fires + 1 end
isTrue("one strike stays inside its fire budget", fires <= sandbox.MaxFires)

--------------------------------------------------------------------------------
-- what was in memory, and what was not
--------------------------------------------------------------------------------

isTrue("a patch that was fully loaded is written off",
    Zones.bucketClaimed(zone, 105, 105))
check("a patch that was only half there is left for later",
    Zones.bucketClaimed(zone, 99, 105), false)

--------------------------------------------------------------------------------
-- ground that arrives late
--------------------------------------------------------------------------------

-- The strip at x = 99 was never in memory when the bomb went off. Load it now,
-- as the game would when a player walks that way.
for y = 90, 109 do
    place(99, y, 0)
end
local late = world["99,105,0"]

for _, fn in ipairs(stubs.registered["LoadGridsquare"] or {}) do fn(late) end
isTrue("loading ground inside a crater queues work", #Blast.jobs > 0)
runToCompletion()

check("the late arrival is levelled too", #late.structure.items, 1)
isTrue("and its patch is now written off", Zones.bucketClaimed(zone, 99, 105))

-- Walking over it again must not level it a second time, or start new fires days
-- after the fact.
local before = #Blast.jobs
for _, fn in ipairs(stubs.registered["LoadGridsquare"] or {}) do fn(late) end
check("loading the same ground again does nothing", #Blast.jobs, before)

-- Ground well outside every crater is nobody's business.
local far = place(400, 400, 0)
for _, fn in ipairs(stubs.registered["LoadGridsquare"] or {}) do fn(far) end
check("ground outside a crater is left alone", #Blast.jobs, 0)
check("and keeps everything", #far.structure.items, 3)

--------------------------------------------------------------------------------
-- vehicles
--------------------------------------------------------------------------------

-- A second strike, with all three tiers in play this time so each ring's
-- treatment of a car can be told apart.
sandbox.FlattenPercent = 20
sandbox.HeavyPercent = 60
sandbox.DestroyVehicles = true

local atZero = makeVehicle(105, 115)            -- dead centre: fireball
local nearby = makeVehicle(112, 115)            -- 7 out of 20: heavy
local outer = makeVehicle(105, 132)             -- 17 out of 20: light
local wellClear = makeVehicle(105, 190)         -- 75 out: nowhere near it

-- The regression: one car whose parts cannot be read used to mark the guard dead
-- and silently spare every car after it.
local awkward = makeVehicle(113, 115, true)
local alsoNearby = makeVehicle(114, 115)

local carPark = Zones.add(105, 115, 20, 30, 72, 0, "test")
Blast.detonate(carPark, nil)
runToCompletion()

isTrue("a car in the fireball is taken out of the world", atZero.removed)
check("a car in the blast wave is not deleted", nearby.removed, false)
isTrue("but every one of its parts is ruined", nearby.ruined >= 3)
isTrue("a car at the edge is wrecked too", outer.ruined >= 3)
check("a car well clear is untouched", wellClear.ruined, 0)
check("and still there", wellClear.removed, false)

isTrue("a car the build cannot read is skipped, not fatal", awkward.ruined == 0)
isTrue("and the car behind it is still wrecked", alsoNearby.ruined >= 3)

-- Deleting a vehicle mutates the list being walked. A forward loop would step
-- over whatever moved into the gap.
check("removing cars does not make the loop skip others",
    (atZero.removed and alsoNearby.ruined >= 3), true)

-- Falling back when the engine will not delete a vehicle.
local stubborn = makeVehicle(105, 300, false, true)
local stubbornZone = Zones.add(105, 300, 20, 30, 72, 0, "test")
Blast.detonate(stubbornZone, nil)
runToCompletion()
check("a car that will not delete is not lost", stubborn.removed, false)
isTrue("it gets wrecked instead", stubborn.ruined >= 3)

-- And the switch turns it all off.
local spared = makeVehicle(105, 400)
sandbox.DestroyVehicles = false
Blast.detonate(Zones.add(105, 400, 20, 30, 72, 0, "test"), nil)
runToCompletion()
check("the sandbox switch spares them", spared.ruined, 0)
check("entirely", spared.removed, false)
sandbox.DestroyVehicles = true

stubs.finish("test_blast")
