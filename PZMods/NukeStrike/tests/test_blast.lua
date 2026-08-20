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

stubs.cell = {
    getGridSquare = function(_, x, y, z) return world[x .. "," .. y .. "," .. z] end,
    getVehicles = function() return javaList({}) end,
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
-- fires stay inside their budget
--------------------------------------------------------------------------------

local fires = 0
for _ in pairs(ignited) do fires = fires + 1 end
isTrue("the fire count stays under the cap", fires <= sandbox.MaxFires)

stubs.finish("test_blast")
