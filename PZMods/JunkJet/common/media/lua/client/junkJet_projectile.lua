--[[
    Flying junk: the game half.

    junkJet_flight.lua does the arithmetic and knows nothing about the world.
    This finds the squares, decides what counts as blocked, draws the thing, and
    drops the real item where it lands.

    Landing is the part that makes the weapon what it is: the round already
    knows it was a toy car, so a toy car goes on the ground and is picked up
    like any other. Nothing special is needed for that - it is an ordinary world
    item the moment it stops.

    Known ground this shares with every other projectile mod, written down
    because none of it is solved here either:

      * Elevation. Junk flies flat. Firing off a balcony will look wrong, and
        Bow and Arrow has the same problem after years.
      * Multiplayer. This simulates on the machine that fired. Other players do
        not see it yet - the shot needs broadcasting and re-running on each
        client, and that is deliberately not attempted blind.
      * Walls. See `obstructed` below; the directional case is genuinely hard
        and the reference mods get it wrong.
]]

require "junkJet_flight"
require "junkJet_ammoRule"

-- A repeating weapon breaks the one-projectile-at-a-time assumption both
-- reference mods are built on. Every shot in the air costs a render and a
-- collision test per tick, so there is a ceiling; past it, junk simply lands at
-- the muzzle rather than queueing up work.
local MAX_IN_FLIGHT = 12

---@type table[]
local inFlight = {}

---@param x number
---@param y number
---@param z number
---@return IsoGridSquare?
local function squareAt(x, y, z)
    local cell = getCell()
    if cell == nil then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
end

--- Whether junk can pass from one square to the next, and what stopped it.
---
--- Deliberately conservative about what it claims to know. The square-based
--- test cannot tell which SIDE of a square a wall sits on, so a shot passing a
--- north-south wall on its way east can read as a hit - the exact bug the
--- reference mods carry. Where the build offers a directional test it is used;
--- otherwise this falls back to the square test and is honest about it in the
--- one place a future fix has to touch.
---@return string? reason
local function obstructed(fromX, fromY, toX, toY, z)
    local target = squareAt(toX, toY, z)

    -- Off the edge of what is loaded. Not a hit; just as far as we go.
    if target == nil then return "unloaded" end

    local from = squareAt(fromX, fromY, z)
    if from ~= nil and from ~= target and from.isBlockedTo ~= nil then
        -- The directional question, asked properly, when the build answers it.
        local ok, blocked = pcall(function() return from:isBlockedTo(target) end)
        if ok and blocked then return "wall" end
    elseif target.isSolid ~= nil and (target:isSolid() or target:isSolidTrans()) then
        return "wall"
    end

    -- Anything standing there stops it. Damage is the firearm's own business -
    -- the game has already resolved the shot - so this only ends the flight.
    if target.getMovingObjects ~= nil then
        local objects = target:getMovingObjects()
        if objects ~= nil and objects:size() > 0 then return "body" end
    end

    return nil
end

--- Put the junk on the ground, where it can be picked up again.
---@param shot table
local function land(shot)
    if shot.itemType == nil then return end

    local square = squareAt(shot.x, shot.y, shot.z)
    if square == nil then return end

    -- Offsets keep it from sitting dead centre, so several rounds landing on
    -- one square are separately visible rather than stacked into one.
    local ok, err = pcall(function()
        square:AddWorldInventoryItem(shot.itemType, shot.x % 1, shot.y % 1, 0)
    end)
    if not ok then
        print("[JunkJet] could not place " .. tostring(shot.itemType) .. ": " .. tostring(err))
    end
end

--- Draw one piece of junk mid-air, if this build can.
---
--- Failure here is cosmetic and must not stop the flight: an invisible round
--- that still lands and can still be picked up is a far better outcome than a
--- Lua error every tick.
---@param shot table
local function draw(shot)
    if shot.itemType == nil then return end
    if Render3DItem == nil then return end

    pcall(function()
        Render3DItem(shot.itemType, shot.x, shot.y, shot.z)
    end)
end

local function tick()
    if #inFlight == 0 then return end

    -- Backwards, so removing a finished shot does not skip the next one.
    for i = #inFlight, 1, -1 do
        local shot = inFlight[i]
        JunkJetFlight.step(shot, obstructed)

        if shot.done then
            land(shot)
            table.remove(inFlight, i)
        else
            draw(shot)
        end
    end
end

JunkJetProjectile = JunkJetProjectile or {}

--- Send a piece of junk on its way.
---
--- Separated from whatever fires it so the same entry point can later be called
--- from a server command, which is what multiplayer will need.
---@param x number
---@param y number
---@param z number
---@param dirX number
---@param dirY number
---@param itemType string?
---@return boolean launched
function JunkJetProjectile.fire(x, y, z, dirX, dirY, itemType)
    if #inFlight >= MAX_IN_FLIGHT then
        -- Over the ceiling: drop it at the muzzle rather than refuse it. The
        -- player still gets their junk back, which is what they care about.
        land({ x = x, y = y, z = z, itemType = itemType })
        return false
    end

    local shot = JunkJetFlight.new(x, y, z, dirX, dirY, { itemType = itemType })
    if shot == nil then return false end

    inFlight[#inFlight + 1] = shot
    return true
end

---@return integer
function JunkJetProjectile.count() return #inFlight end

--------------------------------------------------------------------------------
-- pulling the trigger
--------------------------------------------------------------------------------

local JUNK_JET = "JunkJet.JunkJet_Weapon"

--- Send the next thing in the hopper wherever the shooter is facing.
---
--- Hung on OnWeaponSwing, which is the conventional hook for "a weapon was
--- used". Whether it fires for a ranged weapon on every build is not something
--- this repo can confirm; if junk never flies but the gun still shoots, this is
--- the line to suspect first, and OnPlayerAttackFinished is the alternative.
---
--- The damage is not ours to do. The firearm has already resolved its shot by
--- the time this runs - this is the thing you watch sail across the street, and
--- then pick up.
---@param character IsoGameCharacter
---@param weapon InventoryItem
local function onSwing(character, weapon)
    if character == nil or weapon == nil then return end
    if weapon.getFullType == nil or weapon:getFullType() ~= JUNK_JET then return end

    local facing = character:getForwardDirection()
    if facing == nil then return end

    -- nil when the gun is firing past what it remembered loading. The shot
    -- still happens; there is simply nothing to draw or to leave behind.
    local itemType = JunkJetAmmo.pop(weapon)

    JunkJetProjectile.fire(
        character:getX(), character:getY(), character:getZ(),
        facing:getX(), facing:getY(), itemType)
end

Events.OnTick.Add(tick)

-- Wrapped, like the context menu is: this runs on every swing of every weapon
-- in the game, so an error here would follow the player around.
Events.OnWeaponSwing.Add(function(character, weapon)
    local ok, err = pcall(onSwing, character, weapon)
    if not ok then
        print("[JunkJet] ERROR firing projectile: " .. tostring(err))
    end
end)
