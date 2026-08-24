-- Harness: the flight of a fired piece of junk.
--
-- The whole reason this is arithmetic and not game calls is so it can be
-- checked here. What lands where, what stops it, and - the one that matters for
-- picking your junk back up - that it stops OUTSIDE what blocked it.

next = nil   -- Kahlua has no `next`; see MODDING-NOTES section 4

dofile("PZMods/JunkJet/common/media/lua/shared/junkJet_flight.lua")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        io.write(string.format("FAIL  %-52s got=%s want=%s\n", label, tostring(got), tostring(want)))
    else
        io.write(string.format("ok    %-52s %s\n", label, tostring(got)))
    end
end

local function near(a, b) return math.abs(a - b) < 0.001 end
local function clear() return nil end

--------------------------------------------------------------------------------
io.write("-- a shot with nowhere to go --\n")

-- Direction (0,0) would sit still forever, never travelling far enough to
-- expire. Refused at the door rather than looping somewhere downstream.
check("no direction, no shot", JunkJetFlight.new(10, 10, 0, 0, 0), nil)

--------------------------------------------------------------------------------
io.write("\n-- flying straight --\n")

local shot = JunkJetFlight.new(10, 10, 0, 1, 0, { speed = 1, range = 5 })
check("it starts where it was fired", shot.x, 10)
check("and has not travelled yet", shot.travelled, 0)

JunkJetFlight.step(shot, clear)
check("one tick moves it one tile", shot.x, 11)
check("and not sideways", shot.y, 10)
check("still in the air", shot.done, false)

JunkJetFlight.run(shot, clear)
check("it stops at its range", shot.travelled, 5)
check("having got there", shot.x, 15)
check("and says why it stopped", shot.reason, "spent")

--------------------------------------------------------------------------------
io.write("\n-- direction is normalised --\n")

-- A diagonal shot must not travel further than a straight one just because the
-- numbers were bigger.
local diagonal = JunkJetFlight.new(0, 0, 0, 3, 3, { speed = 1, range = 10 })
JunkJetFlight.run(diagonal, clear)
check("a diagonal covers the same distance", near(diagonal.travelled, 10), true)
check("and lands off both axes", near(diagonal.x, diagonal.y), true)
check("not at the raw direction it was given", near(diagonal.x, 30), false)

--------------------------------------------------------------------------------
io.write("\n-- hitting something --\n")

-- The one that matters for picking your junk back up: a shot stopped by a wall
-- lands against it, NOT inside it. Junk inside a wall cannot be retrieved.
local WALL_AT = 14
local function wallAt14(_, _, toX)
    if toX >= WALL_AT then return "wall" end
    return nil
end

local stopped = JunkJetFlight.new(10, 10, 0, 1, 0, { speed = 1, range = 20 })
JunkJetFlight.run(stopped, wallAt14)
check("it stops on the wall", stopped.done, true)
check("naming what stopped it", stopped.reason, "wall")
check("and lands short of it, not inside", stopped.x, 13)
check("well before its range ran out", stopped.travelled < 20, true)

-- Blocked on the very first tick: it should drop at the shooter's feet rather
-- than move at all.
local pointBlank = JunkJetFlight.new(10, 10, 0, 1, 0, { speed = 1, range = 20 })
JunkJetFlight.run(pointBlank, function() return "zombie" end)
check("point blank stops immediately", pointBlank.reason, "zombie")
check("without moving", pointBlank.x, 10)

--------------------------------------------------------------------------------
io.write("\n-- the shot carries what was fired --\n")

-- The gun remembers what went down the hopper; the shot has to carry it, or
-- there is nothing to place on the ground at the end.
local carried = JunkJetFlight.new(0, 0, 0, 1, 0, { itemType = "Base.ToyCar" })
check("a toy car is still a toy car in flight", carried.itemType, "Base.ToyCar")

--------------------------------------------------------------------------------
io.write("\n-- nothing runs forever --\n")

-- A speed of zero never accumulates range. Without a step ceiling that is a
-- hung game, not a bug report.
local stuck = JunkJetFlight.new(0, 0, 0, 1, 0, { speed = 0, range = 10 })
JunkJetFlight.run(stuck, clear, 50)
check("a zero-speed shot still terminates", stuck.done, true)
check("and admits it was given up on", stuck.reason, "gave up")
check("stepping a finished shot does nothing", JunkJetFlight.step(stuck, clear).x, 0)

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
