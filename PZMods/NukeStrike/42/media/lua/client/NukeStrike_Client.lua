--[[
    Nuke Strike - what the player sees and hears.

    Runs for a connected client, for a co-op host (who is the server and a player
    at once) and in single player. None of it is authoritative: the server has
    already decided what happened, and this file only reacts.

    Distance does the work here. Everybody on the map is told a bomb went off,
    but what that means depends on where they were standing: a white-out and a
    wall of noise on top of it, a flash and a delayed crack a few blocks away, or
    a low rumble from over the horizon a minute's drive out. The sound is
    deliberately late in proportion to the distance, because that is the detail
    that sells it.
]]

if not NukeStrike.isClientSide() then return end

local NS = NukeStrike

-- Ticks per second, used to turn distances into sound delays.
local TICKS = 60

-- How far a flash carries, and how far a sound carries, in tiles.
local FLASH_RANGE = 320
local SOUND_RANGE = 900

-- Beyond this, the blast is heard as a rumble rather than a bang.
local RUMBLE_RANGE = 260

---@type table[] haze zones as last reported by the server
local zones = {}

---@type table? a queued boom: {ticks, volume, sound}
local incoming = nil

---@type table? an inbound strike being counted down: {endMs}
local warning = nil

local flash = 0
local haze = 0
local hazeTarget = 0
local coughCooldown = 0

--------------------------------------------------------------------------------
-- sound
--------------------------------------------------------------------------------

---@param name string
---@param volume number
local function play(name, volume)
    local manager = getSoundManager()
    if manager == nil then return end

    local player = getPlayer()
    local square = player ~= nil and player:getCurrentSquare() or nil

    if square ~= nil then
        local sound, ok = NS.try("PlayWorldSound", function()
            return manager:PlayWorldSound(name, square, 0, 40, volume, false)
        end)
        if ok and sound ~= nil then
            NS.try("BaseSoundEmitter:setVolume", function() sound:setVolume(volume) end)
            return
        end
    end

    NS.try("PlaySound", function() manager:PlaySound(name, false, volume) end)
end

--------------------------------------------------------------------------------
-- the overlay
--------------------------------------------------------------------------------

local Overlay = ISUIElement:derive("NukeStrikeOverlay")

--- One pixel, in the corner, deliberately.
---
--- An element's size is its hit box. The UI manager hands a click to whatever
--- element is under the cursor, so a full screen element swallows every click on
--- the world behind it - and setConsumeMouseEvents(false), which is supposed to
--- stop exactly that, does not. It does not even fail: it succeeds, and the
--- element carries on eating clicks. That is why right-click worked fine until a
--- nuke went off and then stopped for as long as the fog was up.
---
--- drawRect and drawTextCentre are not clipped to the element's bounds, so a one
--- pixel element can still paint the whole screen. The picture is exactly the
--- same; there is simply nothing left to click on.
function Overlay:new()
    local o = ISUIElement:new(0, 0, 1, 1)
    setmetatable(o, self)
    self.__index = self
    return o
end

function Overlay:render()
    local width = getCore():getScreenWidth()
    local height = getCore():getScreenHeight()

    if haze > 0.01 then
        -- A sick yellow-green, thin enough to see through at the edge of the
        -- cloud and thick enough to be frightening at the middle of it.
        self:drawRect(0, 0, width, height, haze * 0.42, 0.42, 0.50, 0.16)

        if haze > 0.25 then
            local pulse = 0.55 + 0.25 * math.sin(NS.realMillis() / 400)
            self:drawTextCentre(getText("IGUI_NukeStrike_Haze"),
                width / 2, 42, 0.75, 0.85, 0.35, pulse * haze, UIFont.Large)
            self:drawTextCentre(getText("IGUI_NukeStrike_HazeHint"),
                width / 2, 74, 0.75, 0.85, 0.35, 0.5 * haze, UIFont.Small)
        end
    end

    if warning ~= nil then
        local left = math.max(0, math.ceil((warning.endMs - NS.realMillis()) / 1000))
        local pulse = 0.6 + 0.4 * math.sin(NS.realMillis() / 180)
        self:drawTextCentre(getText("IGUI_NukeStrike_Incoming") .. "  " .. left,
            width / 2, height * 0.18, 0.9, 0.2, 0.15, pulse, UIFont.Large)
    end

    if flash > 0.01 then
        self:drawRect(0, 0, width, height, flash, 1, 1, 1)
    end
end

---@type table?
local overlay = nil

--- Put the overlay on screen.
---
--- It is only ever up while there is something to draw. Nothing is happening
--- most of the time, and an element that is not there cannot misbehave at all -
--- which is the second half of keeping the mouse working, the first being the
--- one pixel size above.
---@return boolean showing
local function ensureOverlay()
    if overlay ~= nil then return true end

    local element = Overlay:new()
    element:initialise()
    element:instantiate()

    -- Belt and braces on top of the size. None of these are load-bearing any
    -- more; the element is a single pixel whether they work or not.
    NS.try("ISUIElement:setAlwaysOnTop", function() element:setAlwaysOnTop(false) end)
    NS.try("ISUIElement:setCapture", function() element:setCapture(false) end)
    NS.try("UIElement:setConsumeMouseEvents", function()
        element.javaObject:setConsumeMouseEvents(false)
    end)

    element:addToUIManager()
    overlay = element
    return true
end

--- Take it off screen the moment there is nothing left to draw.
local function dropOverlay()
    if overlay == nil then return end
    NS.try("ISUIElement:removeFromUIManager", function() overlay:removeFromUIManager() end)
    overlay = nil
end

--- Whether anything wants drawing right now.
---@return boolean
local function anythingToDraw()
    return flash > 0.01 or haze > 0.01 or hazeTarget > 0.01 or warning ~= nil
end

--------------------------------------------------------------------------------
-- reacting
--------------------------------------------------------------------------------

---@return number? x, number? y
local function playerPosition()
    local player = getPlayer()
    if player == nil then return nil, nil end
    return player:getX(), player:getY()
end

---@param x number
---@param y number
---@return number distance in tiles, or a very large number if we have no player
local function distanceTo(x, y)
    local px, py = playerPosition()
    if px == nil then return 1e9 end
    return NS.dist(px, py, x, y)
end

---@param args table
local function onDetonate(args)
    warning = nil

    local distance = distanceTo(args.x, args.y)

    if distance < FLASH_RANGE then
        flash = math.min(1, 1 - distance / FLASH_RANGE)
        -- Right underneath it, the white-out comes before anything else.
        if distance < args.r then flash = 1 end
    end

    if distance < SOUND_RANGE then
        local volume = math.max(0.15, 1 - distance / SOUND_RANGE)
        local far = distance > RUMBLE_RANGE
        incoming = {
            -- Sound lags the light. Four seconds at two hundred tiles is not
            -- physics, it is the pause that makes a distant one land.
            ticks = math.min(6 * TICKS, math.floor(distance / 50 * TICKS)),
            volume = far and volume * 0.7 or volume,
            sound = far and NS.SOUND_RUMBLE or NS.SOUND_BLAST,
        }
    end
end

---@param args table
local function onWarn(args)
    local seconds = tonumber(args.seconds) or 0
    warning = { endMs = NS.realMillis() + seconds * 1000 }

    local distance = distanceTo(args.x, args.y)
    if distance < SOUND_RANGE then
        play(NS.SOUND_SIREN, math.max(0.2, 1 - distance / SOUND_RANGE))
    end
end

local function onHazeHit()
    if coughCooldown > 0 then return end
    coughCooldown = 30 * TICKS

    local player = getPlayer()
    if player == nil then return end
    NS.try("IsoPlayer:Say", function() player:Say("*coughs*") end)
end

---@param command string
---@param args table?
local function receive(command, args)
    args = args or {}

    if command == "detonate" then
        onDetonate(args)
    elseif command == "warn" then
        onWarn(args)
    elseif command == "zones" then
        zones = args.zones or {}
    elseif command == "hazeHit" then
        onHazeHit()
    elseif command == "message" then
        local text = args.text
        if text ~= nil and text ~= "" then processGeneralMessage(text) end
    end
end

-- The host's own player never receives a broadcast over the wire, so the server
-- half calls this directly instead.
NS.localReceive = receive

---@param module string
---@param command string
---@param args table?
local function onServerCommand(module, command, args)
    if module ~= NS.MODULE then return end
    receive(command, args)
end

--------------------------------------------------------------------------------
-- ticking
--------------------------------------------------------------------------------

local sinceHazeCheck = 0

--- Work out how thick the air is where we are standing. Done on the client from
--- the zone list rather than being pushed by the server, because the server only
--- speaks every ten minutes and you can walk out of a cloud in less than that.
local function recomputeHaze()
    if #zones == 0 then
        hazeTarget = 0
        return
    end

    local px, py = playerPosition()
    if px == nil then
        hazeTarget = 0
        return
    end

    local now = NS.worldHours()
    local worst = 0

    for _, zone in ipairs(zones) do
        local left = (zone.hazeUntil or 0) - now
        if left > 0 then
            local strength = NS.hazeStrength(
                NS.dist(px, py, zone.x, zone.y), zone.hazeR or 0, left, zone.hazeHours or 0)
            if strength > worst then worst = strength end
        end
    end

    hazeTarget = worst
end

local function tick()
    if flash > 0 then
        flash = flash - 0.022
        if flash < 0 then flash = 0 end
    end

    if coughCooldown > 0 then coughCooldown = coughCooldown - 1 end

    if incoming ~= nil then
        incoming.ticks = incoming.ticks - 1
        if incoming.ticks <= 0 then
            play(incoming.sound, incoming.volume)
            incoming = nil
        end
    end

    if warning ~= nil and NS.realMillis() >= warning.endMs then
        warning = nil
    end

    sinceHazeCheck = sinceHazeCheck + 1
    if sinceHazeCheck >= 20 then
        sinceHazeCheck = 0
        recomputeHaze()
    end

    -- Ease towards the target so walking into fallout fades in rather than
    -- snapping on every time the check runs.
    if haze < hazeTarget then
        haze = math.min(hazeTarget, haze + 0.01)
    elseif haze > hazeTarget then
        haze = math.max(hazeTarget, haze - 0.01)
    end

    -- On screen only while it has something to say.
    if anythingToDraw() then
        ensureOverlay()
    else
        dropOverlay()
    end
end

---@param playerIndex integer
---@param player IsoPlayer
local function onCreatePlayer(playerIndex, player)
    if playerIndex ~= 0 or player == nil then return end
    -- Deliberately does NOT put the overlay on screen. There is nothing to draw
    -- at spawn, and a full screen element that is up from the moment you load in
    -- is exactly how the mod used to eat everyone's right-click.
    NS.toHost("sync", {})
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnTick.Add(tick)
