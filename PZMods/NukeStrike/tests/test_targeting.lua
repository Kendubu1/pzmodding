-- The pure half of the mod: what a typed command means, how hard a square is
-- hit, how the sweep walks outwards, and how thick the air is.
--
--     lua5.1 PZMods/NukeStrike/tests/test_targeting.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")
stubs.install({ server = false, client = false, coop = false })
dofile("PZMods/NukeStrike/42/media/lua/shared/NukeStrike_Shared.lua")

local NS = NukeStrike
local check, near, isTrue = stubs.check, stubs.checkNear, stubs.checkTrue

--------------------------------------------------------------------------------
-- parsing
--------------------------------------------------------------------------------

local function parse(line)
    return NS.parseCommand(NS.words(line))
end

check("empty line asks for help", parse("").sub, "help")
check("help", parse("help").sub, "help")
check("status", parse("status").sub, "status")
check("abort", parse("abort").sub, "abort")
check("clear", parse("clear").sub, "clear")
check("coords", parse("coords").sub, "coords")

local spaced = parse("10500 9500")
check("spaced coordinates are a strike", spaced.sub, "detonate")
check("spaced x", spaced.x, 10500)
check("spaced y", spaced.y, 9500)
check("no radius override by default", spaced.radius, nil)

local comma = parse("10500,9500")
check("comma-joined x", comma.x, 10500)
check("comma-joined y", comma.y, 9500)

local trailing = parse("10500, 9500")
check("trailing comma x", trailing.x, 10500)
check("trailing comma y", trailing.y, 9500)

local sized = parse("10500 9500 120")
check("radius override", sized.radius, 120)

local here = parse("here")
check("here is a strike", here.sub, "detonate")
isTrue("here is flagged", here.here)

check("here with a radius", parse("here 60").radius, 60)

local onPlayer = parse("player Bob")
check("player target", onPlayer.name, "Bob")
check("player target is a strike", onPlayer.sub, "detonate")
check("player target with a radius", parse("player Bob 90").radius, 90)

local rolled = parse("roll 10500 9500")
isTrue("roll is flagged", rolled.roll)
check("roll still carries the target", rolled.x, 10500)

local both = parse("roll now here")
isTrue("roll and now compose (roll)", both.roll)
isTrue("roll and now compose (now)", both.immediate)
isTrue("roll and now compose (here)", both.here)

-- "on" is an alias for "player", because it is what people type.
check("on <name>", parse("on Bob").name, "Bob")

isTrue("gibberish is rejected", parse("banana").err ~= nil)
isTrue("a roll with no target is rejected", parse("roll").err ~= nil)
isTrue("a player with no name is rejected", parse("player").err ~= nil)
isTrue("a stray word after a target is rejected", parse("here sideways").err ~= nil)

--------------------------------------------------------------------------------
-- damage tiers
--------------------------------------------------------------------------------

local function tier(dist) return NS.tier(dist, 200, 40, 75) end

check("ground zero is flattened", tier(0), "flatten")
check("the flatten boundary is inclusive", tier(80), "flatten")
check("past it is heavy", tier(80.1), "heavy")
check("the heavy boundary is inclusive", tier(150), "heavy")
check("past it is light", tier(150.1), "light")
check("the edge is still light", tier(200), "light")
check("outside is nothing", tier(200.1), nil)
check("a zero radius hits nothing", NS.tier(0, 0, 40, 75), nil)

-- A heavy ring set inside the flatten ring must not invert the tiers: the heavy
-- band collapses to nothing rather than the two swapping over.
check("crossed thresholds still flatten the middle", NS.tier(90, 200, 60, 10), "flatten")
check("crossed thresholds leave no heavy band", NS.tier(130, 200, 60, 10), "light")

--------------------------------------------------------------------------------
-- the outward sweep
--------------------------------------------------------------------------------

check("ring 0 is one square", NS.ringLength(0), 1)
check("ring 1 is eight squares", NS.ringLength(1), 8)
check("ring 7 is fifty-six squares", NS.ringLength(7), 56)

for _, r in ipairs({ 1, 2, 5, 13 }) do
    local seen = {}
    local duplicates, offRing = 0, 0

    for i = 0, NS.ringLength(r) - 1 do
        local x, y = NS.ringSquare(100, 200, r, i)
        local key = x .. ":" .. y
        if seen[key] then duplicates = duplicates + 1 end
        seen[key] = true

        if math.max(math.abs(x - 100), math.abs(y - 200)) ~= r then
            offRing = offRing + 1
        end
    end

    check("ring " .. r .. " has no repeats", duplicates, 0)
    check("ring " .. r .. " stays on the ring", offRing, 0)
end

local cx, cy = NS.ringSquare(100, 200, 0, 0)
check("ring 0 x is the centre", cx, 100)
check("ring 0 y is the centre", cy, 200)

--------------------------------------------------------------------------------
-- buckets
--------------------------------------------------------------------------------

check("origin bucket", NS.bucketKey(0, 0), "0,0")
check("a bucket is ten wide", NS.bucketKey(9, 9), "0,0")
check("the next bucket over", NS.bucketKey(10, 0), "1,0")
check("a map coordinate", NS.bucketKey(10507, 9503), "1050,950")

--------------------------------------------------------------------------------
-- fallout
--------------------------------------------------------------------------------

near("the middle of the cloud is full strength", NS.hazeStrength(0, 300, 72, 72), 1)
near("the inner half holds", NS.hazeStrength(150, 300, 72, 72), 1)
near("three quarters out is half strength", NS.hazeStrength(225, 300, 72, 72), 0.5)
check("outside the cloud is clean", NS.hazeStrength(300, 300, 72, 72), 0)
check("expired haze is clean", NS.hazeStrength(0, 300, 0, 72), 0)
check("no cloud is clean", NS.hazeStrength(0, 0, 72, 72), 0)

-- The last fifth of the lifetime fades out rather than switching off.
near("half way through the fade", NS.hazeStrength(0, 300, 7.2, 72), 0.5)
near("still full before the fade starts", NS.hazeStrength(0, 300, 20, 72), 1)

--------------------------------------------------------------------------------
-- the die
--------------------------------------------------------------------------------

local lowest, highest = 7, 0
for _ = 1, 500 do
    local value = NS.rollDie()
    if value < lowest then lowest = value end
    if value > highest then highest = value end
end
check("a d6 never rolls below one", lowest, 1)
check("a d6 never rolls above six", highest, 6)

stubs.finish("test_targeting")
