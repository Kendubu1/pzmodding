--[[
    Nuke Strike - what the player hears.

    Runs for a connected client, for a co-op host (who is the server and a player
    at once) and in single player. None of it is authoritative: the server has
    already decided what happened, and this file only reacts.

    Distance does the work here. Everybody on the map is told a bomb went off,
    but what that means depends on where they were standing: a wall of noise on
    top of it, a delayed crack a few blocks away, or a low rumble from over the
    horizon a minute's drive out. The sound is deliberately late in proportion to
    the distance, because that is the detail that sells it.

    There is deliberately NO screen overlay - no fog tint, no white flash, no
    countdown drawn over the game. There used to be, and it cost the player their
    right-click for as long as the fog was up.

    The reason is worth keeping written down, because a screen tint is an obvious
    thing to want to add back. A UI element's SIZE is its hit box: the UI manager
    hands a click to whatever element sits under the cursor, so a full screen
    element swallows every click on the world behind it.
    setConsumeMouseEvents(false) is supposed to prevent that and does not - it
    does not even fail, it succeeds and the element carries on eating clicks. A
    cosmetic tint is not worth that risk, so everything this file says now goes
    through sound and text, neither of which can take the mouse away.
]]

if not NukeStrike.isClientSide() then return end

local NS = NukeStrike

-- Ticks per second, used to turn distances into sound delays.
local TICKS = 60

-- How far a sound carries, in tiles.
local SOUND_RANGE = 900

-- Beyond this, the blast is heard as a rumble rather than a bang.
local RUMBLE_RANGE = 260

-- In-game minutes between "you are breathing this" reminders.
local COUGH_SECONDS = 30

---@type table? a queued boom: {ticks, volume, sound}
local incoming = nil

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
-- reacting
--------------------------------------------------------------------------------

---@param x number
---@param y number
---@return number distance in tiles, or a very large number if we have no player
local function distanceTo(x, y)
    local player = getPlayer()
    if player == nil then return 1e9 end
    return NS.dist(player:getX(), player:getY(), x, y)
end

---@param args table
local function onDetonate(args)
    local distance = distanceTo(args.x, args.y)
    if distance >= SOUND_RANGE then return end

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

---@param args table
local function onWarn(args)
    local distance = distanceTo(args.x, args.y)
    if distance < SOUND_RANGE then
        play(NS.SOUND_SIREN, math.max(0.2, 1 - distance / SOUND_RANGE))
    end
end

--- Being in the fallout. Floating text over the character and a cough, rather
--- than anything drawn over the screen.
local function onHazeHit()
    if coughCooldown > 0 then return end
    coughCooldown = COUGH_SECONDS * TICKS

    local player = getPlayer()
    if player == nil then return end

    NS.try("IsoPlayer:Say", function() player:Say("*coughs*") end)
    NS.try("HaloTextHelper", function()
        HaloTextHelper.addTextWithArrow(player, getText("IGUI_NukeStrike_Haze"), false,
            HaloTextHelper.getColorRed())
    end)
end

---@param command string
---@param args table?
local function receive(command, args)
    args = args or {}

    if command == "detonate" then
        onDetonate(args)
    elseif command == "warn" then
        onWarn(args)
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

local function tick()
    if coughCooldown > 0 then coughCooldown = coughCooldown - 1 end

    if incoming ~= nil then
        incoming.ticks = incoming.ticks - 1
        if incoming.ticks <= 0 then
            play(incoming.sound, incoming.volume)
            incoming = nil
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(tick)
