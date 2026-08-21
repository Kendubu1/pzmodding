--[[
    Nuke Strike - the blast itself.

    Two problems shape this file.

    The first is size. A 200 tile radius is about 125,000 tiles, and each one may
    have eight storeys of building on it. Resolving that inside one frame would
    hang the server for long enough to time every client out. So the blast is a
    job queue worked through a few hundred tiles per tick, sweeping outwards ring
    by ring from ground zero - which also happens to look like a shockwave.

    The second is that most of the map is not there. Squares outside the area
    around a player are not loaded, and a square that is not loaded cannot be
    destroyed. So the sweep only levels what exists right now, and the zone is
    left on record; when ground inside a crater loads later, LoadGridsquare
    catches it and levels it on arrival.

    That split is why fires and kills are gated on the strike being fresh.
    Levelling a house you walk up to a week later is right - the bomb did that.
    Setting it on fire a week later, or killing the zombies who wandered in after
    the fact, is not.
]]

if not NukeStrike.isHost() then return end

local NS = NukeStrike
local Blast = NS.Blast

-- How long after the strike its fires and kills still apply, in in-game minutes
-- of the world clock. Ground that loads after this is levelled cold.
local FRESH_MINUTES = 20

-- Chance an object is taken off the square, by tier. Structure means the walls,
-- furniture and trees sitting on the square; fittings means the doors, windows
-- and wall-mounted things, which are held in a separate list by the engine and
-- give up more easily.
local REMOVE_STRUCTURE = { flatten = 100, heavy = 85, light = 20 }
local REMOVE_FITTINGS = { flatten = 100, heavy = 95, light = 60 }

-- Chance a living thing on the square dies, by tier.
local KILL_CHANCE = { flatten = 100, heavy = 90, light = 50 }

-- Relative willingness of each tier to catch fire. The absolute number of fires
-- is set by the MaxFires option and spread over the whole blast, so these only
-- decide where they cluster.
local FIRE_WEIGHT = { flatten = 1.0, heavy = 0.8, light = 0.25 }

---@type table[]
Blast.jobs = {}

--------------------------------------------------------------------------------
-- guarded engine calls
--------------------------------------------------------------------------------

local function callTransmitRemove(sq, obj) sq:transmitRemoveItemFromSquare(obj) end
local function callRemoveTileObject(sq, obj) sq:RemoveTileObject(obj) end
local function callStartFire(sq) sq:StartFire() end
local function callFireManager(sq) IsoFireManager.StartFire(getCell(), sq, true, 100) end
local function callBurn(sq) sq:Burn(true) end
local function callRemoveWorldItems(sq) sq:removeAllWorldObjects() end
local function callKill(character, killer) character:Kill(killer) end
local function callKillNoSource(character) character:Kill(nil) end
local function callVanish(zombie)
    zombie:removeFromWorld()
    zombie:removeFromSquare()
end
local function callGetFloor(sq) return sq:getFloor() end
local function callGetVehicles(cell) return cell:getVehicles() end
local function callRemoveVehicle(vehicle) vehicle:permanentlyRemove() end
local function callVehicleSquare(vehicle) return vehicle:getSquare() end

-- Ruin every part in one call. The first argument is the base quality and the
-- second is the chance a part spawns damaged, so nothing survives this.
local function callRuinParts(vehicle) vehicle:setGeneralPartCondition(0, 100) end

-- The bodywork itself. This is the call that makes a car LOOK wrecked rather
-- than merely being undriveable, and it takes the panel to smash, not a boolean.
local function callSmash(vehicle, location) vehicle:setSmashed(location) end

-- Redraw. Part conditions and smashed panels do not show up on their own; the
-- damage overlay has to be told to rebuild, which is why a car whose parts were
-- all ruined still sat there looking showroom fresh.
local function callDamageOverlay(vehicle) vehicle:updateDamageOverlayLater() end

-- And tell the other players. Conditions changed on the server do not reach a
-- client on their own, so in multiplayer everyone else keeps seeing an intact car.
local function callTransmitParts(vehicle)
    local parts = vehicle:getParts()
    if parts == nil then return end
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part ~= nil then vehicle:transmitPartCondition(part) end
    end
end

local function callCrashDamage(vehicle, force) vehicle:addRandomDamageFromCrash(nil, force) end

-- The panels setSmashed understands. Tried one at a time so a build that names
-- them differently still gets whichever ones it does recognise.
local SMASH_PANELS = { "Front", "Rear", "Left", "Right" }

--- Take one object off a square. transmitRemoveItemFromSquare is the removal
--- that reaches the other players; RemoveTileObject is the local fallback for
--- builds or objects it refuses.
---@param sq IsoGridSquare
---@param obj IsoObject
local function removeObject(sq, obj)
    local _, ok = NS.try("transmitRemoveItemFromSquare", callTransmitRemove, sq, obj)
    if ok then return end
    NS.try("RemoveTileObject", callRemoveTileObject, sq, obj)
end

---@param sq IsoGridSquare
local function ignite(sq)
    local _, ok = NS.try("IsoGridSquare:StartFire", callStartFire, sq)
    if ok then return true end
    local _, viaManager = NS.try("IsoFireManager.StartFire", callFireManager, sq)
    return viaManager
end

--------------------------------------------------------------------------------
-- one square
--------------------------------------------------------------------------------

---@param chance integer 0..100
---@return boolean
local function roll(chance)
    if chance >= 100 then return true end
    if chance <= 0 then return false end
    return ZombRand(100) < chance
end

--- Clear a list of objects off a square. Iterates backwards because removing
--- from the front of a Java list underneath a forward loop skips half of it.
---@param sq IsoGridSquare
---@param list ArrayList?
---@param chance integer
---@param keep IsoObject? the one object never to remove (the ground floor)
local function clearList(sq, list, chance, keep)
    if list == nil then return end

    for i = list:size() - 1, 0, -1 do
        local obj = list:get(i)
        if obj ~= nil and obj ~= keep and roll(chance) then
            removeObject(sq, obj)
        end
    end
end

--- Kill whatever is standing here.
---
--- Inside the fireball zombies are deleted rather than killed. A corpse for
--- every zombie in a six block radius is thousands of objects the server then
--- carries for the rest of the save, and there is nothing left to leave a body.
--- Players always get a real death, so the game handles it properly.
---@param sq IsoGridSquare
---@param tier string
---@param killer IsoPlayer?
local function killLiving(sq, tier, killer)
    local movers = sq:getMovingObjects()
    if movers == nil then return end

    local chance = KILL_CHANCE[tier] or 0
    local killPlayers = NS.getOption("KillPlayers", true) == true

    for i = movers:size() - 1, 0, -1 do
        local target = movers:get(i)
        if target ~= nil and roll(chance) then
            if instanceof(target, "IsoPlayer") then
                if killPlayers then
                    local _, ok = NS.try("IsoPlayer:Kill", callKill, target, killer)
                    if not ok then NS.try("IsoPlayer:Kill(nil)", callKillNoSource, target) end
                end
            elseif instanceof(target, "IsoZombie") then
                -- Bandits and the Week One NPCs are IsoZombie under the skin, so
                -- they are covered by this arm rather than needing their own.
                local vanished = false
                if tier == "flatten" then
                    local _, ok = NS.try("IsoZombie:removeFromWorld", callVanish, target)
                    vanished = ok
                end
                if not vanished then
                    local _, ok = NS.try("IsoZombie:Kill", callKill, target, killer)
                    if not ok then NS.try("IsoZombie:Kill(nil)", callKillNoSource, target) end
                end
            elseif instanceof(target, "IsoAnimal") then
                local _, ok = NS.try("IsoAnimal:Kill", callKill, target, killer)
                if not ok then NS.try("IsoAnimal:Kill(nil)", callKillNoSource, target) end
            end
        end
    end
end

--- Level one square at one height.
---@param sq IsoGridSquare
---@param tier string
---@param isUpper boolean a storey above ground, whose floor goes too
local function levelSquare(sq, tier, isUpper)
    -- The ground floor tile is the one thing kept, so the ruins are walkable
    -- rather than a hole into nothing. Upper storeys lose their floors, which is
    -- what makes a building come down instead of just losing its walls.
    local keep = nil
    if not isUpper then
        local floor, ok = NS.try("IsoGridSquare:getFloor", callGetFloor, sq)
        if ok then keep = floor end
    end

    clearList(sq, sq:getSpecialObjects(), REMOVE_FITTINGS[tier] or 0, keep)
    clearList(sq, sq:getObjects(), REMOVE_STRUCTURE[tier] or 0, keep)

    if tier == "flatten" or tier == "heavy" then
        NS.try("IsoGridSquare:removeAllWorldObjects", callRemoveWorldItems, sq)
    end
end

--------------------------------------------------------------------------------
-- one column of the map
--------------------------------------------------------------------------------

--- Everything at one (x, y), from the top storey down.
---@param job table
---@param x integer
---@param y integer
---@return boolean loaded false when this ground is not in memory
local function applyColumn(job, x, y)
    local zone = job.zone

    local dist = NS.dist(x, y, zone.x, zone.y)
    local tier = NS.tier(dist, zone.r)
    if tier == nil then return true end -- a ring corner outside the circle

    local cell = getCell()
    if cell == nil then return false end

    local ground = cell:getGridSquare(x, y, 0)
    if ground == nil then return false end

    -- Upper storeys first: taking the top off before the bottom keeps the game
    -- from briefly holding a floating room.
    local storeys = {}
    local maxFloors = math.floor(NS.getOption("MaxFloors", 8))
    for z = 1, maxFloors - 1 do
        local sq = cell:getGridSquare(x, y, z)
        if sq == nil then break end
        storeys[#storeys + 1] = sq
    end

    for i = #storeys, 1, -1 do
        if job.fresh then killLiving(storeys[i], tier, job.killer) end
        levelSquare(storeys[i], tier, true)
    end

    if job.fresh then killLiving(ground, tier, job.killer) end
    levelSquare(ground, tier, false)

    if tier == "flatten" or tier == "heavy" then
        NS.try("IsoGridSquare:Burn", callBurn, ground)
    end

    -- The fire budget belongs to the strike, not to this job. A patch of ground
    -- that loads a minute later draws from the same pool the sweep did, so the
    -- cap is a cap on the strike however many pieces it ends up being done in.
    if job.fresh and (zone.firesLeft or 0) > 0
        and ZombRand(10000) < math.floor(job.fireOdds * (FIRE_WEIGHT[tier] or 0)) then
        if ignite(ground) then zone.firesLeft = zone.firesLeft - 1 end
    end

    return true
end

--------------------------------------------------------------------------------
-- jobs
--------------------------------------------------------------------------------

--- Remember whether every square in a ten-by-ten patch was in memory. Only
--- patches that were completely covered get written off as done; one that was
--- half loaded is left unclaimed so it gets another go when the rest arrives.
---@param job table
---@param x integer
---@param y integer
---@param loaded boolean
local function notePatch(job, x, y, loaded)
    local key = NS.bucketKey(x, y)
    local patch = job.patches[key]
    if patch == nil then
        patch = { missed = false }
        job.patches[key] = patch
    end
    if not loaded then patch.missed = true end
end

--- Write the completed patches into the zone so they are never redone.
---@param job table
local function settle(job)
    local zone = job.zone
    zone.buckets = zone.buckets or {}

    for key, patch in pairs(job.patches) do
        if patch.missed then
            -- Unclaim, so the ground gets levelled when it does load.
            zone.buckets[key] = nil
        else
            zone.buckets[key] = true
        end
    end
end

--- One slice of the outward sweep.
---@param job table
---@param budget integer
---@return integer squares examined
local function stepSweep(job, budget)
    local used = 0

    while used < budget do
        if job.r > job.maxR then
            job.done = true
            return used
        end

        local length = NS.ringLength(job.r)
        if job.i >= length then
            job.r = job.r + 1
            job.i = 0
        else
            local x, y = NS.ringSquare(job.zone.x, job.zone.y, job.r, job.i)
            job.i = job.i + 1
            used = used + 1
            notePatch(job, x, y, applyColumn(job, x, y))
        end
    end

    return used
end

--- One slice of a single ten-by-ten patch that loaded after the fact.
---@param job table
---@param budget integer
---@return integer squares examined
local function stepPatch(job, budget)
    local used = 0
    local side = NS.BUCKET

    while used < budget do
        if job.i >= side * side then
            job.done = true
            return used
        end

        local x = job.x0 + (job.i % side)
        local y = job.y0 + math.floor(job.i / side)
        job.i = job.i + 1
        used = used + 1
        notePatch(job, x, y, applyColumn(job, x, y))
    end

    return used
end

--------------------------------------------------------------------------------
-- the worker
--------------------------------------------------------------------------------

local function work()
    local job = Blast.jobs[1]
    if job == nil then return end

    local budget = math.max(10, math.floor(NS.getOption("SquaresPerTick", 250)))

    while job ~= nil and budget > 0 do
        local used
        if job.kind == "sweep" then
            used = stepSweep(job, budget)
        else
            used = stepPatch(job, budget)
        end

        budget = budget - math.max(used, 0)

        if job.done then
            settle(job)
            table.remove(Blast.jobs, 1)
            job = Blast.jobs[1]
        elseif used <= 0 then
            -- Nothing consumed and not finished: bail rather than spin.
            return
        end
    end
end

--------------------------------------------------------------------------------
-- entry points
--------------------------------------------------------------------------------

--- How many fires this square is allowed to want, per ten thousand rolls.
---
--- The cap is a total for the whole strike, so it has to be spread over the
--- whole area. Rolling a flat chance per square instead would burn the entire
--- budget in the first few rings and leave the outer blast untouched.
---@param radius number
---@return number
local function fireOddsPer10k(radius)
    local maxFires = NS.getOption("MaxFires", 250)
    if maxFires <= 0 then return 0 end

    local area = math.pi * radius * radius
    if area <= 0 then return 0 end

    local eagerness = NS.getOption("FireChance", 55) / 50
    return math.min(10000, (maxFires / area) * 10000 * eagerness)
end

-- Chance a vehicle that survived the blast is left burning, by tier.
local VEHICLE_FIRE = { flatten = 100, heavy = 85, light = 35 }

--- Do as much to one vehicle as the build will allow.
---
--- There is no "explode this car" call in the game - vehicles have no explode
--- method at all - so a wrecked car is made out of four separate things, and
--- leaving any one of them out is what makes a strike look like it missed:
---
---   1. Ruin the parts. Dead engine, flat tyres, nothing that will start.
---   2. Smash the bodywork. This is the part that is actually visible; ruined
---      parts alone leave a showroom-fresh car that happens not to drive.
---   3. Rebuild the damage overlay, or none of the above is drawn.
---   4. Transmit the part conditions, or nobody else on the server sees it.
---
--- Then set it alight, because burning is as close to exploding as the game
--- gets, and a charred husk reads as a nuke went off here far better than a
--- missing car does.
---
--- Every call is wrapped on its own, per vehicle. A shared guard here would mean
--- one awkward car disabling the whole feature for the rest of the session.
---@param vehicle BaseVehicle
---@param tier string
---@param cell IsoCell
---@param vx number
---@param vy number
---@return boolean removed, boolean wrecked, boolean burning
local function ruinVehicle(vehicle, tier, cell, vx, vy)
    local _, wrecked = NS.try("BaseVehicle:setGeneralPartCondition", callRuinParts, vehicle)

    -- A nuke is a very large crash.
    NS.try("BaseVehicle:addRandomDamageFromCrash", callCrashDamage, vehicle,
        tier == "flatten" and 100 or 60)

    for _, panel in ipairs(SMASH_PANELS) do
        local _, smashed = NS.try("BaseVehicle:setSmashed:" .. panel, callSmash, vehicle, panel)
        if smashed then wrecked = true end
    end

    NS.try("BaseVehicle:updateDamageOverlayLater", callDamageOverlay, vehicle)
    NS.try("BaseVehicle:transmitPartCondition", callTransmitParts, vehicle)

    local burning = false
    if ZombRand(100) < (VEHICLE_FIRE[tier] or 0) then
        local square = NS.try("BaseVehicle:getSquare", callVehicleSquare, vehicle)
        if square == nil then
            square = cell:getGridSquare(math.floor(vx), math.floor(vy), 0)
        end
        if square ~= nil then burning = ignite(square) == true end
    end

    -- Last resort. If this build would not let us mark the car as damaged in any
    -- way at all, an intact car sitting at ground zero is worse than no car, so
    -- inside the fireball it goes.
    if not wrecked and tier == "flatten" then
        local _, gone = NS.try("BaseVehicle:permanentlyRemove", callRemoveVehicle, vehicle)
        if gone then return true, false, false end
    end

    return false, wrecked, burning
end

--- Ruin the vehicles caught in the blast. Cheap enough to do in one pass: there
--- are tens of vehicles in a cell, not thousands.
---
--- Walks the list backwards, because removing a vehicle mutates the list it came
--- from and a forward loop would skip the car behind every one it deleted.
---@param zone table
local function wreckVehicles(zone)
    if NS.getOption("DestroyVehicles", true) ~= true then return end

    local cell = getCell()
    if cell == nil then return end

    local vehicles, ok = NS.try("IsoCell:getVehicles", callGetVehicles, cell)
    if not ok or vehicles == nil then
        print("[NukeStrike] vehicles: this build will not hand over the vehicle list, none touched")
        return
    end

    local total = vehicles:size()
    local found, removed, wrecked, burning = 0, 0, 0, 0

    for i = total - 1, 0, -1 do
        local vehicle = vehicles:get(i)
        if vehicle ~= nil then
            local okPosition, vx, vy = pcall(function() return vehicle:getX(), vehicle:getY() end)
            if okPosition and vx ~= nil then
                local tier = NS.tier(NS.dist(vx, vy, zone.x, zone.y), zone.r)
                if tier ~= nil then
                    found = found + 1
                    local wasRemoved, wasWrecked, wasBurning = ruinVehicle(vehicle, tier, cell, vx, vy)
                    if wasRemoved then removed = removed + 1 end
                    if wasWrecked then wrecked = wrecked + 1 end
                    if wasBurning then burning = burning + 1 end
                end
            end
        end
    end

    -- Said out loud every strike. "It did nothing to the cars" is impossible to
    -- diagnose without knowing whether it found none or found six and failed.
    print(string.format(
        "[NukeStrike] vehicles: %d of %d loaded were in the blast - %d removed, %d wrecked, %d set alight",
        found, total, removed, wrecked, burning))
end

--- Start levelling a strike that has just landed.
---@param zone table
---@param killer IsoPlayer?
function Blast.detonate(zone, killer)
    zone.firesLeft = math.floor(NS.getOption("MaxFires", 250))

    Blast.jobs[#Blast.jobs + 1] = {
        kind = "sweep",
        zone = zone,
        killer = killer,
        r = 0,
        i = 0,
        maxR = zone.r,
        fresh = true,
        fireOdds = fireOddsPer10k(zone.r),
        patches = {},
    }

    wreckVehicles(zone)
end

--- Queue one ten-by-ten patch of a crater that has just come into memory.
---@param zone table
---@param x integer
---@param y integer
local function queuePatch(zone, x, y)
    local side = NS.BUCKET
    local nowMinutes = NS.worldHours() * 60
    local fresh = (nowMinutes - (zone.born or 0) * 60) <= FRESH_MINUTES

    Blast.jobs[#Blast.jobs + 1] = {
        kind = "patch",
        zone = zone,
        killer = nil,
        x0 = math.floor(x / side) * side,
        y0 = math.floor(y / side) * side,
        i = 0,
        fresh = fresh,
        fireOdds = fresh and fireOddsPer10k(zone.r) or 0,
        patches = {},
    }
end

--- Ground arriving inside a crater it never saw.
---@param sq IsoGridSquare
local function onLoadGridsquare(sq)
    if sq == nil then return end
    if NS.Zones.count == nil or NS.Zones.count() == 0 then return end

    -- Only the ground layer decides; the storeys above come with it.
    if sq:getZ() ~= 0 then return end

    local x, y = sq:getX(), sq:getY()
    local zone = NS.Zones.craterAt(x, y)
    if zone == nil then return end
    if not NS.Zones.claimBucket(zone, x, y) then return end

    queuePatch(zone, x, y)
end

Events.OnTick.Add(work)
Events.LoadGridsquare.Add(onLoadGridsquare)
