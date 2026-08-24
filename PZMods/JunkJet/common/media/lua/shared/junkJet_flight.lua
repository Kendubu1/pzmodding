--[[
    Where a fired piece of junk is, one tick at a time.

    Pure arithmetic on purpose. Nothing here touches a square, an item or a
    player - the caller hands in a function that answers "is the way from here
    to there blocked, and by what". That keeps the part with the decisions in it
    testable offline, and it means the collision test can be improved later
    without touching the flight at all.

    That separation matters more than usual here. Both mods that already do this
    - Bow and Arrow, and the Projectile and Targeting System example - share a
    collision bug: they check whether a square holds a wall tile, but not which
    SIDE of the square the wall is on, so a shot passing a north-south wall on
    its way east registers as a hit. Fixing that is a change to one injected
    function, not to any of this.
]]

JunkJetFlight = JunkJetFlight or {}

-- Tiles per tick. Fast enough to read as a shot rather than a lob, slow enough
-- that the collision test is not stepping over whole squares.
JunkJetFlight.SPEED = 0.6

-- How far a piece of junk carries before it drops. Roughly the weapon's
-- MaxRange, which is 16.
JunkJetFlight.RANGE = 16

--- Start a shot.
---@param x number
---@param y number
---@param z number
---@param dirX number direction, need not be normalised
---@param dirY number
---@param opts table? {speed, range, itemType}
---@return table? shot nil when the direction is nowhere
function JunkJetFlight.new(x, y, z, dirX, dirY, opts)
    opts = opts or {}

    local length = math.sqrt((dirX * dirX) + (dirY * dirY))
    -- A shot with no direction would sit on the spot forever, never travelling
    -- far enough to expire. Refused rather than special-cased downstream.
    if length <= 0 then return nil end

    return {
        x = x,
        y = y,
        z = z,
        dx = dirX / length,
        dy = dirY / length,
        speed = opts.speed or JunkJetFlight.SPEED,
        range = opts.range or JunkJetFlight.RANGE,
        itemType = opts.itemType,
        travelled = 0,
        done = false,
        reason = nil,
    }
end

--- Advance one tick.
---
--- On being stopped by something, the shot stays on the last square it actually
--- reached rather than the one it was refused: junk should land against the
--- wall, not inside it.
---@param shot table
---@param obstructed fun(fromX:number, fromY:number, toX:number, toY:number, z:number):string?
---@return table shot
function JunkJetFlight.step(shot, obstructed)
    if shot == nil or shot.done then return shot end

    local nextX = shot.x + (shot.dx * shot.speed)
    local nextY = shot.y + (shot.dy * shot.speed)

    if obstructed ~= nil then
        local reason = obstructed(shot.x, shot.y, nextX, nextY, shot.z)
        if reason ~= nil then
            shot.done = true
            shot.reason = reason
            return shot
        end
    end

    shot.x = nextX
    shot.y = nextY
    shot.travelled = shot.travelled + shot.speed

    -- Out of puff. It has moved onto this square first, so it drops here rather
    -- than one square short.
    if shot.travelled >= shot.range then
        shot.done = true
        shot.reason = "spent"
    end

    return shot
end

--- Run a shot to its conclusion. Bounded by a step count as well as by range,
--- because a caller supplying a speed of zero would otherwise never finish.
---@param shot table
---@param obstructed function?
---@param maxSteps integer?
---@return table shot
function JunkJetFlight.run(shot, obstructed, maxSteps)
    local limit = maxSteps or 500
    local steps = 0

    while shot ~= nil and not shot.done and steps < limit do
        JunkJetFlight.step(shot, obstructed)
        steps = steps + 1
    end

    if shot ~= nil and not shot.done then
        shot.done = true
        shot.reason = "gave up"
    end
    return shot
end
