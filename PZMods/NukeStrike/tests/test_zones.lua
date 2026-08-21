-- The record of what has been nuked: craters that outlive the explosion, haze
-- that expires, and the bookkeeping that stops ground being levelled twice.
--
--     lua5.1 PZMods/NukeStrike/tests/test_zones.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")
stubs.install({ server = false, client = false, coop = false })

dofile("PZMods/NukeStrike/42/media/lua/shared/NukeStrike_Shared.lua")
dofile("PZMods/NukeStrike/42/media/lua/server/NukeStrike_Zones.lua")

local NS = NukeStrike
local Zones = NS.Zones
local check, near, isTrue = stubs.check, stubs.checkNear, stubs.checkTrue

check("nothing is on record to begin with", Zones.count(), 0)

--------------------------------------------------------------------------------
-- recording a strike
--------------------------------------------------------------------------------

local zone = Zones.add(10500, 9500, 200, 300, 72, 0, "kendubu1")

check("the strike is on record", Zones.count(), 1)
check("centre x", zone.x, 10500)
check("centre y", zone.y, 9500)
check("radius", zone.r, 200)
check("haze radius", zone.hazeR, 300)
check("haze expires three days out", zone.hazeUntil, 72)
check("who called it", zone.by, "kendubu1")

--------------------------------------------------------------------------------
-- the crater
--------------------------------------------------------------------------------

local found, tier = Zones.craterAt(10500, 9500)
check("ground zero is in the crater", found and found.id, zone.id)
check("ground zero is flattened", tier, "flatten")

local _, edgeTier = Zones.craterAt(10500 + 190, 9500)
check("the edge is lightly hit", edgeTier, "light")

check("well outside is not in a crater", Zones.craterAt(10500 + 400, 9500), nil)

-- A second, smaller strike right on top of the first. A square inside both
-- belongs to whichever one buried it deepest.
local inner = Zones.add(10500, 9500, 40, 60, 72, 0, "kendubu1")
local overlap = Zones.craterAt(10505, 9500)
check("overlapping strikes: the deeper one owns the square", overlap.id, inner.id)

local outside = Zones.craterAt(10500 + 100, 9500)
check("outside the smaller one, the bigger one still owns it", outside.id, zone.id)

--------------------------------------------------------------------------------
-- the haze
--------------------------------------------------------------------------------

near("the crater is choking at hour zero", Zones.hazeAt(10500, 9500, 0), 1)
near("the edge of the cloud is clean", Zones.hazeAt(10500 + 300, 9500, 0), 0)
near("three quarters out is half strength", Zones.hazeAt(10500 + 225, 9500, 0), 0.5)

near("still full strength on the third day", Zones.hazeAt(10500, 9500, 50), 1)
near("fading as it clears", Zones.hazeAt(10500, 9500, 64.8), 0.5)
check("clean once it has run out", Zones.hazeAt(10500, 9500, 72), 0)
check("clean long after", Zones.hazeAt(10500, 9500, 500), 0)

isTrue("haze is reported while it lasts", Zones.anyHaze(10))
check("and not after", Zones.anyHaze(100), false)

--------------------------------------------------------------------------------
-- buckets
--------------------------------------------------------------------------------

check("a fresh patch is unclaimed", Zones.bucketClaimed(zone, 10503, 9507), false)
isTrue("claiming it works the first time", Zones.claimBucket(zone, 10503, 9507))
check("and not the second", Zones.claimBucket(zone, 10503, 9507), false)
isTrue("the whole ten-by-ten patch is claimed", Zones.bucketClaimed(zone, 10509, 9500))
check("but not the patch next door", Zones.bucketClaimed(zone, 10510, 9500), false)

--------------------------------------------------------------------------------
-- reporting
--------------------------------------------------------------------------------

check("the report covers every strike", #Zones.report(0), 2)
isTrue("the report names the caller", string.find(Zones.report(0)[1], "kendubu1", 1, true) ~= nil)
isTrue("the report says when the haze has gone",
    string.find(Zones.report(100)[1], "cleared", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- the list does not grow without limit
--------------------------------------------------------------------------------

for i = 1, NS.MAX_ZONES + 5 do
    Zones.add(1000 + i, 1000, 50, 75, 72, 0, "test")
end
check("the oldest strikes are dropped", Zones.count(), NS.MAX_ZONES)
check("the first strike is gone", Zones.craterAt(10500, 9500), nil)

--------------------------------------------------------------------------------
-- clearing
--------------------------------------------------------------------------------

local dropped = Zones.clear()
check("clearing reports what it dropped", dropped, NS.MAX_ZONES)
check("and leaves nothing behind", Zones.count(), 0)
check("no craters after a clear", Zones.craterAt(1001, 1000), nil)
check("no haze after a clear", Zones.hazeAt(1001, 1000, 0), 0)

stubs.finish("test_zones")
