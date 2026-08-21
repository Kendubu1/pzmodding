--[[
    Nuke Strike - shared definitions.

    Loaded on both halves. Holds the network module name, the sandbox accessors,
    the pure geometry and command parsing, and the small networking wrappers that
    let the same call work in single player, a co-op host game and a dedicated
    server without the callers caring which one they are in.

    The sub-tables (Zones, Blast, Server) are created HERE rather than in the
    files that fill them. The game loads a folder's Lua files alphabetically, so
    server/NukeStrike_Blast.lua runs before server/NukeStrike_Zones.lua; anything
    doing `local Zones = NS.Zones` at load time in Blast.lua would capture nil
    forever. Creating the tables in shared - which loads before both - means every
    file captures the same table whatever the order.
]]

NukeStrike = NukeStrike or {}
local NS = NukeStrike

NS.VERSION = "1.0.0"

-- Module name used by sendClientCommand / sendServerCommand.
NS.MODULE = "NukeStrike"

-- Key for the global ModData table holding the crater and haze records.
NS.MODDATA_KEY = "NukeStrike"

NS.Zones = NS.Zones or {}
NS.Blast = NS.Blast or {}
NS.Server = NS.Server or {}

-- Sound events, defined in media/scripts/NukeStrike_sounds.txt. Change these two
-- lines to point at another mod's sound event if you would rather use its audio.
NS.SOUND_BLAST = "NukeStrikeBlast"
NS.SOUND_RUMBLE = "NukeStrikeRumble"
NS.SOUND_SIREN = "NukeStrikeSiren"

-- Side of the square buckets used to remember which ground has already been
-- flattened. Nothing to do with engine chunks - it only has to be consistent
-- with itself, and a bucket is one entry in the save instead of a hundred.
NS.BUCKET = 10

-- Most zones that will ever matter, oldest dropped first. Each one carries a
-- table of flattened buckets, so the list is not free to keep forever.
NS.MAX_ZONES = 32

--------------------------------------------------------------------------------
-- where we are running
--------------------------------------------------------------------------------

--- Co-op host detection, guarded in case the global is missing on some builds.
---@return boolean
local function coopHost()
    if isCoopHost == nil then return false end
    local ok, value = pcall(isCoopHost)
    return ok and value == true
end
NS.isCoopHost = coopHost

--- True where the authoritative half runs: single player, the host of a co-op
--- game (who runs the server in-process) and a dedicated server. False only for
--- a player connected to someone else's server.
---
--- A co-op host reports isClient() == false and isServer() == false, so `not
--- isClient()` catches all three; the coopHost() arm is belt and braces in case
--- a build ever reports differently.
---@return boolean
function NS.isHost()
    return (not isClient()) or coopHost()
end

--- True where the player-facing half runs: single player, a co-op host and a
--- connected client. False on a dedicated server, which has no screen.
---@return boolean
function NS.isClientSide()
    return (not isServer()) or coopHost()
end

--- True in single player only, where neither send*Command function has anywhere
--- to go and both halves live in one Lua state.
---@return boolean
function NS.isSingle()
    return (not isServer()) and (not isClient()) and (not coopHost())
end

--------------------------------------------------------------------------------
-- options
--------------------------------------------------------------------------------

--- Read a sandbox option, falling back to a default if the options failed to
--- load (which is what happens when the mod is enabled mid-save).
---@param name string
---@param default any
---@return any
function NS.getOption(name, default)
    local vars = SandboxVars and SandboxVars.NukeStrike
    if vars == nil then return default end
    local value = vars[name]
    if value == nil then return default end
    return value
end

---@return boolean
function NS.isEnabled()
    return NS.getOption("Enabled", true) == true
end

---@return integer
function NS.blastRadius()
    return math.max(1, math.floor(NS.getOption("BlastRadius", 200)))
end

--- Haze reaches further than the blast: the fire does the damage, the fallout
--- drifts. A percentage of the blast radius, so one option scales both.
---@param radius number blast radius
---@return integer
function NS.hazeRadius(radius)
    local pct = NS.getOption("HazeRadiusPercent", 150)
    return math.floor(radius * pct / 100)
end

--------------------------------------------------------------------------------
-- guarded engine calls
--------------------------------------------------------------------------------

-- Which engine calls have already failed. This mod pokes at a lot of surface -
-- object removal, fire, body damage, vehicles - and the names drift between
-- builds. A call that raises is reported and then skipped for the rest of the
-- session rather than throwing sixty times a second inside the blast loop.
--
-- Giving up quickly matters more than it sounds. Kahlua prints a caught error's
-- whole stack trace anyway, even from inside a pcall, so a call that fails once
-- per object across a hundred thousand tiles does not just fail quietly - it
-- writes a hundred thousand stack traces into console.txt while the server tries
-- to run a blast.
local dead = {}
local failures = {}

-- Most calls are asking "does this build have this method", where one failure is
-- the whole answer. A few are made once per object, where a single failure might
-- be one awkward object rather than a missing method. Those get a few goes
-- first: enough that one bad car does not spare every car behind it, few enough
-- that a method this build simply does not have stops after a handful of traces.
NS.ALLOWANCE = {
    ["BaseVehicle:parts"] = 5,
    ["BaseVehicle:permanentlyRemove"] = 5,
    ["BaseVehicle:getSquare"] = 5,
}

--- Call an engine function, tolerating its absence.
---@param label string identifies the call in the log and in the skip list
---@param fn function
---@return any result, boolean ok
function NS.try(label, fn, a, b, c, d)
    if dead[label] then return nil, false end

    local ok, result = pcall(fn, a, b, c, d)
    if not ok then
        local count = (failures[label] or 0) + 1
        failures[label] = count

        if count >= (NS.ALLOWANCE[label] or 1) then
            dead[label] = true
            print("[NukeStrike] " .. label .. " is unavailable on this build, skipping it from here on: "
                .. tostring(result))
        else
            print("[NukeStrike] " .. label .. " failed (" .. count .. "), carrying on: " .. tostring(result))
        end
        return nil, false
    end

    return result, true
end

--- Whether a guarded call has been given up on. Used by the tests and by the
--- haze effects, which walk a list of alternatives and want to stop asking.
---@param label string
---@return boolean
function NS.isDead(label)
    return dead[label] == true
end

--------------------------------------------------------------------------------
-- geometry (pure - covered by tests/test_targeting.lua)
--------------------------------------------------------------------------------

---@return number
function NS.dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

--- How hard a square this far from ground zero is hit.
---
---   flatten - inside the fireball. Everything above the ground goes.
---   heavy   - the blast wave. Most structures collapse, fires everywhere.
---   light   - the edge. Windows out, roofs stripped, scattered fires.
---
--- nil means outside the blast entirely.
---@param dist number
---@param radius number
---@param flattenPct number? defaults to the sandbox option
---@param heavyPct number? defaults to the sandbox option
---@return string? tier
function NS.tier(dist, radius, flattenPct, heavyPct)
    if radius <= 0 or dist > radius then return nil end

    flattenPct = flattenPct or NS.getOption("FlattenPercent", 40)
    heavyPct = heavyPct or NS.getOption("HeavyPercent", 75)
    if heavyPct < flattenPct then heavyPct = flattenPct end

    if dist <= radius * flattenPct / 100 then return "flatten" end
    if dist <= radius * heavyPct / 100 then return "heavy" end
    return "light"
end

--- The bucket a world coordinate belongs to. Negative coordinates do not occur
--- on the Knox County map but floor() keeps the maths honest if they ever do.
---@return string
function NS.bucketKey(x, y)
    local b = NS.BUCKET
    return math.floor(x / b) .. "," .. math.floor(y / b)
end

--- The i'th square of the ring `r` squares out from (cx, cy), walking clockwise
--- from the top-left corner. Ring 0 is the centre square. Used to sweep the
--- blast outwards so the destruction arrives as a wave rather than all at once.
---@param cx integer
---@param cy integer
---@param r integer
---@param i integer 0 .. NS.ringLength(r) - 1
---@return integer x, integer y
function NS.ringSquare(cx, cy, r, i)
    if r <= 0 then return cx, cy end

    local side = 2 * r
    i = i % (4 * side)

    if i < side then return cx - r + i, cy - r end
    if i < 2 * side then return cx + r, cy - r + (i - side) end
    if i < 3 * side then return cx + r - (i - 2 * side), cy + r end
    return cx - r, cy + r - (i - 3 * side)
end

---@param r integer
---@return integer
function NS.ringLength(r)
    if r <= 0 then return 1 end
    return 8 * r
end

--- Haze strength at a point, 0 (clean) to 1 (right on top of the crater).
--- Holds near full strength over the inner half of the cloud and falls away
--- towards the edge, then fades out over the last fifth of its lifetime so the
--- air clears rather than switching off.
---@param dist number
---@param hazeRadius number
---@param hoursLeft number
---@param totalHours number
---@return number
function NS.hazeStrength(dist, hazeRadius, hoursLeft, totalHours)
    if hazeRadius <= 0 or hoursLeft <= 0 or dist >= hazeRadius then return 0 end

    local byDistance = math.min(1, (1 - dist / hazeRadius) * 2)

    local byTime = 1
    if totalHours > 0 then
        local fade = totalHours * 0.2
        if fade > 0 and hoursLeft < fade then byTime = hoursLeft / fade end
    end

    return byDistance * byTime
end

--------------------------------------------------------------------------------
-- command parsing (pure - covered by tests/test_targeting.lua)
--------------------------------------------------------------------------------

---@param word string?
---@return number?
local function number(word)
    if word == nil then return nil end
    return tonumber(word)
end

--- Split a line into words.
---@param text string
---@return string[]
function NS.words(text)
    local out = {}
    for word in string.gmatch(text or "", "%S+") do
        out[#out + 1] = word
    end
    return out
end

--- Pull "10500 9500" or "10500,9500" off the front of a word list.
---@param parts string[]
---@param from integer index of the first word to look at
---@return number? x, number? y, integer next index after the coordinates
local function coordinates(parts, from)
    local first = parts[from]
    if first == nil then return nil, nil, from end

    local cx, cy = string.match(first, "^(-?%d+)%s*,%s*(-?%d+)$")
    if cx ~= nil then return tonumber(cx), tonumber(cy), from + 1 end

    local x = number((string.gsub(first, ",", "")))
    local y = number(parts[from + 1])
    if x ~= nil and y ~= nil then return x, y, from + 2 end

    return nil, nil, from
end

--- Parse the words after `/nuke` into an intent the server can act on.
---
--- Understood forms:
---   (nothing)             help
---   help | status | abort | clear | coords
---   here [radius]         strike where you are standing
---   <x> <y> [radius]      strike a map coordinate ("x,y" also works)
---   player <name> [radius]
---   now <target...>       skip the warning countdown
---   roll <target...>      roll a d6, and only detonate on a six
---
--- `roll` and `now` compose: `/nuke roll now 10500 9500` is legal.
---@param parts string[] the words AFTER "/nuke"
---@return table intent {sub, x, y, here, name, radius, immediate, roll, err}
function NS.parseCommand(parts)
    local intent = { sub = "help" }

    local i = 1
    local target = false

    while parts[i] ~= nil do
        local word = string.lower(parts[i])

        if word == "roll" then
            intent.roll = true
            intent.sub = "detonate"
            i = i + 1
        elseif word == "now" then
            intent.immediate = true
            intent.sub = "detonate"
            i = i + 1
        elseif word == "here" then
            intent.sub = "detonate"
            intent.here = true
            target = true
            i = i + 1
        elseif word == "player" or word == "on" then
            intent.sub = "detonate"
            intent.name = parts[i + 1]
            if intent.name == nil then
                intent.err = "no player name given"
                return intent
            end
            target = true
            i = i + 2
        elseif word == "status" or word == "abort" or word == "clear"
            or word == "coords" or word == "help" then
            intent.sub = word
            return intent
        elseif not target then
            local x, y, nextIndex = coordinates(parts, i)
            if x == nil then
                intent.err = "do not understand '" .. tostring(parts[i]) .. "'"
                return intent
            end
            intent.sub = "detonate"
            intent.x, intent.y = math.floor(x), math.floor(y)
            target = true
            i = nextIndex
        else
            -- A bare number once the target is known is the radius override.
            local radius = number(parts[i])
            if radius == nil then
                intent.err = "do not understand '" .. tostring(parts[i]) .. "'"
                return intent
            end
            intent.radius = math.floor(radius)
            i = i + 1
        end
    end

    if intent.sub == "detonate" and not target then
        intent.err = "no target: give coordinates, 'here', or 'player <name>'"
    end

    return intent
end

--- A d6. Uses the game's RNG when there is one so a multiplayer roll comes from
--- the same source as everything else the server randomises.
---@return integer 1..6
function NS.rollDie()
    if ZombRand ~= nil then
        local ok, value = pcall(ZombRand, 6)
        if ok and value ~= nil then return value + 1 end
    end
    return math.random(1, 6)
end

--------------------------------------------------------------------------------
-- time
--------------------------------------------------------------------------------

--- In-game hours since the world began. The clock the haze is measured against,
--- because it survives a save and follows the day-length setting.
---@return number
function NS.worldHours()
    local time = getGameTime()
    if time == nil then return 0 end
    local ok, value = pcall(function() return time:getWorldAgeHours() end)
    if ok and value ~= nil then return value end
    return 0
end

--- Real milliseconds, for the launch countdown. That one is a drama device and
--- should not stretch with the in-game day length.
---@return number
function NS.realMillis()
    if getTimestampMs ~= nil then
        local ok, value = pcall(getTimestampMs)
        if ok and value ~= nil then return value end
    end
    return getTimestamp() * 1000
end

--------------------------------------------------------------------------------
-- players
--------------------------------------------------------------------------------

--- Every player the host can reach, as a plain array. getOnlinePlayers() is the
--- multiplayer answer and is empty or nil in single player, where the one local
--- player is the whole list.
---@return IsoPlayer[]
function NS.players()
    local out = {}

    local online = getOnlinePlayers and getOnlinePlayers() or nil
    if online ~= nil and online:size() > 0 then
        for i = 0, online:size() - 1 do
            local player = online:get(i)
            if player ~= nil then out[#out + 1] = player end
        end
        return out
    end

    local player = getPlayer and getPlayer() or nil
    if player ~= nil then out[1] = player end
    return out
end

--------------------------------------------------------------------------------
-- networking
--------------------------------------------------------------------------------

-- Set by the client half so the host half can reach it directly in single player
-- and in a co-op host game, where a broadcast does not loop back to the machine
-- that sent it.
---@type function?
NS.localReceive = nil

--- Client -> host. In single player and on a co-op host the server half is in
--- this very Lua state, so we call it rather than pretending to be on a network.
---@param sub string
---@param args table?
function NS.toHost(sub, args)
    if isClient() then
        sendClientCommand(getPlayer(), NS.MODULE, sub, args or {})
    elseif NS.Server.handle ~= nil then
        NS.Server.handle(getPlayer(), sub, args or {})
    end
end

--- Host -> one player.
---@param player IsoPlayer?
---@param command string
---@param args table?
function NS.toPlayer(player, command, args)
    if player == nil then return end

    -- The host's own player is not reachable over the wire.
    if NS.localReceive ~= nil and getPlayer ~= nil and player == getPlayer() then
        NS.localReceive(command, args or {})
        return
    end

    if not NS.isSingle() then
        sendServerCommand(player, NS.MODULE, command, args or {})
    end
end

--- Host -> everyone.
---@param command string
---@param args table?
function NS.broadcast(command, args)
    if not NS.isSingle() then
        sendServerCommand(NS.MODULE, command, args or {})
    end
    if NS.localReceive ~= nil then
        NS.localReceive(command, args or {})
    end
end

--- Host -> one player, as a line of chat.
---@param player IsoPlayer?
---@param text string
function NS.tell(player, text)
    NS.toPlayer(player, "message", { text = text })
end
