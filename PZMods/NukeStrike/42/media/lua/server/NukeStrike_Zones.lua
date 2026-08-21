--[[
    Nuke Strike - the record of what has been nuked.

    A strike is not a one-off event. Two things outlive the explosion:

      * The crater. Most of a 200 tile radius is not loaded when the bomb goes
        off, and squares that are not loaded cannot be touched. So the zone is
        written down, and any ground that loads inside it later gets levelled on
        arrival. Walk towards a strike you never saw and you still find ruins.

      * The haze. Fallout is a place and a deadline: a centre, a radius and an
        hour of the world's life at which it clears.

    Both live in the global ModData table, which the game saves and reloads with
    the world, so a server restart does not undo a war.
]]

if not NukeStrike.isHost() then return end

local NS = NukeStrike
local Zones = NS.Zones

---@type table?
local data = nil

--------------------------------------------------------------------------------
-- storage
--------------------------------------------------------------------------------

--- The live table. Global ModData is written into the save with the world, so
--- there is nothing to flush: everything below edits this table in place and the
--- game keeps it.
---
--- Note what is deliberately NOT here: ModData.transmit(). That pushes the whole
--- table to every client, and this one grows a bucket entry for each ten-by-ten
--- patch of levelled ground - thousands of them after a couple of strikes.
--- Clients have no use for any of it either: the fallout is applied server-side
--- and nothing is drawn from it.
---@return table
local function store()
    if data == nil then
        data = ModData.getOrCreate(NS.MODDATA_KEY)
        data.zones = data.zones or {}
        data.nextId = data.nextId or 1
    end
    return data
end

--- Every zone on record, newest last.
---@return table[]
function Zones.all()
    return store().zones
end

---@return integer
function Zones.count()
    return #store().zones
end

--- Record a strike.
---@param x integer
---@param y integer
---@param radius integer
---@param hazeRadius integer
---@param hazeHours number
---@param now number world hours
---@param by string? who called it
---@return table zone
function Zones.add(x, y, radius, hazeRadius, hazeHours, now, by)
    local shelf = store()

    local zone = {
        id = shelf.nextId,
        x = x,
        y = y,
        r = radius,
        hazeR = hazeRadius,
        hazeHours = hazeHours,
        born = now,
        hazeUntil = now + hazeHours,
        by = by or "",
        -- Buckets of ground already levelled, so a chunk that loads twice is not
        -- set on fire twice. Keyed by NS.bucketKey().
        buckets = {},
    }

    shelf.nextId = shelf.nextId + 1
    shelf.zones[#shelf.zones + 1] = zone

    -- Craters are permanent, but the bookkeeping is not free: each zone ends up
    -- holding a bucket entry for every ten-by-ten patch of levelled ground. Past
    -- a few dozen strikes the oldest ones stop earning their place in the save.
    while #shelf.zones > NS.MAX_ZONES do
        table.remove(shelf.zones, 1)
    end

    return zone
end

--- Forget everything. Ground already destroyed stays destroyed - this only stops
--- the mod from levelling ground that has not loaded yet, and clears the haze.
---@return integer how many zones were dropped
function Zones.clear()
    local shelf = store()
    local dropped = #shelf.zones
    shelf.zones = {}
    return dropped
end

--------------------------------------------------------------------------------
-- lookups
--------------------------------------------------------------------------------

-- How badly each tier hurts, for comparing two strikes over the same ground.
local SEVERITY = { light = 1, heavy = 2, flatten = 3 }

--- The zone whose crater covers this point, if any.
---
--- Where strikes overlap the harsher one wins, and where they are equally harsh
--- the newer one does. That second rule is what matters in practice: ground
--- somebody rebuilt inside an old crater belongs to the bomb that just landed on
--- it, so it is levelled again, with fresh fires, rather than being written off
--- as already ruined.
---@param x number
---@param y number
---@return table? zone, string? tier
function Zones.craterAt(x, y)
    local best, bestTier, bestSeverity = nil, nil, 0

    for _, zone in ipairs(store().zones) do
        local tier = NS.tier(NS.dist(x, y, zone.x, zone.y), zone.r)
        if tier ~= nil then
            local severity = SEVERITY[tier] or 0
            -- >= rather than >, because the list runs oldest to newest.
            if severity >= bestSeverity then
                best, bestTier, bestSeverity = zone, tier, severity
            end
        end
    end

    return best, bestTier
end

--- Haze strength at a point, 0 to 1. Overlapping clouds do not add up; the worst
--- one is what you are breathing.
---@param x number
---@param y number
---@param now number world hours
---@return number
function Zones.hazeAt(x, y, now)
    local worst = 0

    for _, zone in ipairs(store().zones) do
        local left = (zone.hazeUntil or 0) - now
        if left > 0 and (zone.hazeR or 0) > 0 then
            local strength = NS.hazeStrength(
                NS.dist(x, y, zone.x, zone.y),
                zone.hazeR,
                left,
                zone.hazeHours or 0)
            if strength > worst then worst = strength end
        end
    end

    return worst
end

--- True the first time this square's bucket is claimed for a zone. The caller
--- levels the bucket; every later load of the same ground gets false and is left
--- alone.
---@param zone table
---@param x number
---@param y number
---@return boolean
function Zones.claimBucket(zone, x, y)
    zone.buckets = zone.buckets or {}

    local key = NS.bucketKey(x, y)
    if zone.buckets[key] then return false end

    zone.buckets[key] = true
    return true
end

---@param zone table
---@param x number
---@param y number
---@return boolean
function Zones.bucketClaimed(zone, x, y)
    return zone.buckets ~= nil and zone.buckets[NS.bucketKey(x, y)] == true
end

--------------------------------------------------------------------------------
-- reporting
--------------------------------------------------------------------------------

--- Human-readable lines for /nuke status.
---@param now number
---@return string[]
function Zones.report(now)
    local lines = {}

    for _, zone in ipairs(store().zones) do
        local left = (zone.hazeUntil or 0) - now
        local haze
        if left > 0 then
            haze = string.format("haze %.0fh left, %d tiles", left, zone.hazeR or 0)
        else
            haze = "haze cleared"
        end

        lines[#lines + 1] = string.format(
            "#%d at %d,%d - radius %d, %s%s",
            zone.id, zone.x, zone.y, zone.r, haze,
            (zone.by ~= nil and zone.by ~= "") and (" (called by " .. zone.by .. ")") or "")
    end

    return lines
end

--- Whether any haze is still out there. Cheap enough for the ten-minute tick.
---@param now number
---@return boolean
function Zones.anyHaze(now)
    for _, zone in ipairs(store().zones) do
        if (zone.hazeUntil or 0) > now and (zone.hazeR or 0) > 0 then return true end
    end
    return false
end
