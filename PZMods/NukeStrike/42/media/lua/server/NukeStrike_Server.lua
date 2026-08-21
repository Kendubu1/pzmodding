--[[
    Nuke Strike - commands, the countdown, and the fallout.

    Runs wherever the world is authoritative: single player, the host of a co-op
    game, and a dedicated server. Nothing a client sends is trusted - the client
    half only types the command, and every decision about whether a strike is
    allowed, where it lands and who it hurts is made here.
]]

if not NukeStrike.isHost() then return end

local NS = NukeStrike
local Server = NS.Server
local Zones = NS.Zones
local Blast = NS.Blast

-- The strike that has been called but has not landed yet. One at a time: a
-- second call while the sirens are going replaces the first, which is what you
-- want when you have just typed the wrong coordinates.
---@type table?
local pending = nil

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

---@param player IsoPlayer?
---@return string
local function nameOf(player)
    if player == nil then return "someone" end
    local ok, username = pcall(function() return player:getUsername() end)
    if ok and username ~= nil and username ~= "" then return username end
    return "someone"
end

---@param username string?
---@return IsoPlayer?
local function findOnline(username)
    if username == nil then return nil end
    local wanted = string.lower(username)

    for _, player in ipairs(NS.players()) do
        if string.lower(nameOf(player)) == wanted then return player end
    end
    return nil
end

--- Whether this player may call a strike. Single player never asks: it is your
--- own world and there is nobody to grief.
---@param player IsoPlayer?
---@return boolean
local function allowed(player)
    if NS.isSingle() then return true end
    if NS.getOption("AdminOnly", true) ~= true then return true end
    if player == nil then return false end

    local ok, admin = pcall(function() return player:isAccessLevel("admin") end)
    return ok and admin == true
end

--- Say something about a strike. Normally everyone hears it; with announcements
--- switched off only the person who called it does, so an admin running a quiet
--- game still gets told their command worked.
---@param text string
---@param caller IsoPlayer?
local function announce(text, caller)
    if NS.getOption("AnnounceGlobally", true) == true then
        NS.broadcast("message", { text = text })
    else
        NS.tell(caller, text)
    end
end

--- Tell every client which haze zones exist, so they can draw the air.
local function pushZones()
    NS.broadcast("zones", { zones = Zones.snapshot(NS.worldHours()) })
end

--------------------------------------------------------------------------------
-- detonation
--------------------------------------------------------------------------------

--- Land a strike.
---@param player IsoPlayer? who called it, used as the killer for the corpses
---@param x integer
---@param y integer
---@param radius integer
local function fire(player, x, y, radius)
    local now = NS.worldHours()
    local hazeHours = NS.getOption("HazeHours", 72)

    local zone = Zones.add(x, y, radius, NS.hazeRadius(radius), hazeHours, now, nameOf(player))

    NS.broadcast("detonate", {
        x = x,
        y = y,
        r = radius,
        hazeR = zone.hazeR,
    })

    announce(string.format(
        "A nuclear device has detonated at %d, %d. Blast radius %d tiles. Fallout for the next %d hours.",
        x, y, radius, hazeHours), player)

    Blast.detonate(zone, player)
    pushZones()

    print(string.format("[NukeStrike] detonation at %d,%d radius %d called by %s",
        x, y, radius, nameOf(player)))
end

--- Sound the sirens, then land the strike when they stop.
---@param player IsoPlayer?
---@param x integer
---@param y integer
---@param radius integer
---@param immediate boolean
local function arm(player, x, y, radius, immediate)
    local seconds = math.floor(NS.getOption("WarningSeconds", 30))
    if immediate or seconds <= 0 then
        pending = nil
        fire(player, x, y, radius)
        return
    end

    pending = {
        x = x,
        y = y,
        r = radius,
        at = NS.realMillis() + seconds * 1000,
        by = player,
    }

    NS.broadcast("warn", { x = x, y = y, r = radius, seconds = seconds })
    announce(string.format(
        "INCOMING: a strike is inbound on %d, %d. Impact in %d seconds.", x, y, seconds), player)
end

--- Watches the countdown. Runs every tick and does nothing at all until a strike
--- has been called, which is the whole cost of it.
local function watchCountdown()
    if pending == nil then return end
    if NS.realMillis() < pending.at then return end

    local shot = pending
    pending = nil
    fire(shot.by, shot.x, shot.y, shot.r)
end

--------------------------------------------------------------------------------
-- fallout
--------------------------------------------------------------------------------

-- Every way we know of to make breathing fallout unpleasant. Each is tried on
-- its own and a call that this build does not have is dropped for the session
-- rather than throwing every ten minutes. The list is deliberately more than one
-- deep: which of these exist has moved between builds.
local EFFECTS = {
    {
        label = "haze:torso",
        apply = function(player, damage)
            player:getBodyDamage():getBodyPart(BodyPartType.Torso_Upper):AddDamage(damage)
        end,
    },
    {
        label = "haze:sickness",
        apply = function(player, damage)
            local bd = player:getBodyDamage()
            bd:setFoodSicknessLevel(math.min(100, bd:getFoodSicknessLevel() + damage * 2))
        end,
    },
    {
        label = "haze:endurance",
        apply = function(player, damage)
            local stats = player:getStats()
            stats:setEndurance(math.max(0, stats:getEndurance() - damage / 100))
        end,
    },
}

--- How much of the fallout a player's kit keeps out. A mask helps a lot, a
--- hazmat suit helps more, and the pair of them together still leaves a little
--- through, because standing in it is meant to be a bad idea.
---@param player IsoPlayer
---@return number 0 .. 0.95
local function protection(player)
    local worn = player:getWornItems()
    if worn == nil then return 0 end

    local mask, suit = false, false

    for i = 0, worn:size() - 1 do
        local slot = worn:get(i)
        local item = slot ~= nil and slot:getItem() or nil
        if item ~= nil then
            local ok, fullType = pcall(function() return item:getFullType() end)
            local name = (ok and fullType ~= nil) and string.lower(fullType) or ""

            if string.find(name, "hazmat", 1, true) then suit = true end
            if string.find(name, "gasmask", 1, true)
                or string.find(name, "gas_mask", 1, true)
                or string.find(name, "respirator", 1, true) then
                mask = true
            end

            local tagged = NS.try("InventoryItem:hasTag", function(it) return it:hasTag("GasMask") end, item)
            if tagged == true then mask = true end
        end
    end

    local blocked = 0
    if mask then blocked = blocked + 0.5 end
    if suit then blocked = blocked + 0.45 end
    return math.min(0.95, blocked)
end

---@param player IsoPlayer
---@param strength number 0..1
local function breatheHaze(player, strength)
    local damage = NS.getOption("HazeDamage", 6.0) * strength * (1 - protection(player))
    if damage <= 0 then return end

    for _, effect in ipairs(EFFECTS) do
        NS.try(effect.label, effect.apply, player, damage)
    end

    NS.toPlayer(player, "hazeHit", { strength = strength })
end

--------------------------------------------------------------------------------
-- bandits in the fallout
--------------------------------------------------------------------------------

local function callZombieList(cell) return cell:getZombieList() end
local function callBanditFlag(zombie) return zombie:getVariableBoolean("Bandit") end
local function callModData(zombie) return zombie:getModData() end
local function callKillZombie(zombie) return zombie:Kill(nil) end

--- Whether this zombie is really a person.
---
--- The Bandits mod builds its NPCs out of IsoZombie: the same class, flagged
--- with a "Bandit" variable and given a Lua brain in its mod data. Either mark
--- is enough, and a plain zombie has neither - so with no Bandits mod installed
--- this quietly finds nothing and costs one variable read per zombie.
---@param zombie IsoZombie
---@return boolean
local function isBandit(zombie)
    local flagged = NS.try("IsoZombie:getVariableBoolean", callBanditFlag, zombie)
    if flagged == true then return true end

    local data = NS.try("IsoZombie:getModData", callModData, zombie)
    return data ~= nil and data.brain ~= nil
end

--- Fallout does not care that a bandit has no lungs to speak for it.
---
--- Zombies are left alone - they are already dead, and killing every zombie that
--- wanders into a three-day cloud would quietly clear the map. Bandits are
--- living people, so they get the same exposure a player does, at the same pace:
--- damage accumulates in their mod data and kills them at the point a player
--- standing in the same air would have died.
---@param now number world hours
local function banditsBreathe(now)
    if NS.getOption("HazeKillsBandits", true) ~= true then return end

    local cell = getCell()
    if cell == nil then return end

    local zombies, ok = NS.try("IsoCell:getZombieList", callZombieList, cell)
    if not ok or zombies == nil then return end

    local perTick = NS.getOption("HazeDamage", 6.0)
    if perTick <= 0 then return end

    for i = zombies:size() - 1, 0, -1 do
        local zombie = zombies:get(i)
        if zombie ~= nil then
            local okPosition, x, y = pcall(function() return zombie:getX(), zombie:getY() end)
            if okPosition and x ~= nil then
                local strength = Zones.hazeAt(x, y, now)
                if strength > 0 and isBandit(zombie) then
                    local data = NS.try("IsoZombie:getModData", callModData, zombie)
                    if data ~= nil then
                        data.nukeExposure = (data.nukeExposure or 0) + strength * perTick
                        if data.nukeExposure >= 100 then
                            NS.try("IsoZombie:Kill(nil)", callKillZombie, zombie)
                        end
                    end
                end
            end
        end
    end
end

--- The fallout tick. Expires nothing on its own - a zone's haze is a deadline,
--- not a countdown - it just applies the air to whoever is standing in it.
local function falloutTick()
    local now = NS.worldHours()
    if not Zones.anyHaze(now) then return end

    for _, player in ipairs(NS.players()) do
        local ok, x, y = pcall(function() return player:getX(), player:getY() end)
        if ok then
            local strength = Zones.hazeAt(x, y, now)
            if strength > 0 then breatheHaze(player, strength) end
        end
    end

    banditsBreathe(now)
    pushZones()
end

--------------------------------------------------------------------------------
-- commands
--------------------------------------------------------------------------------

---@param player IsoPlayer?
---@param intent table from NS.parseCommand
local function detonateCommand(player, intent)
    local x, y

    if intent.here then
        if player == nil then
            NS.tell(player, "There is nobody here to nuke.")
            return
        end
        x, y = math.floor(player:getX()), math.floor(player:getY())
    elseif intent.name ~= nil then
        local target = findOnline(intent.name)
        if target == nil then
            NS.tell(player, "No player online called '" .. tostring(intent.name) .. "'.")
            return
        end
        x, y = math.floor(target:getX()), math.floor(target:getY())
    else
        x, y = intent.x, intent.y
    end

    if x == nil or y == nil then
        NS.tell(player, "No target. Try /nuke 10500 9500, or /nuke here.")
        return
    end
    if x < 0 or y < 0 or x > 40000 or y > 40000 then
        NS.tell(player, "That is not on the map. Coordinates run from 0 to about 15000 on Knox County.")
        return
    end

    local radius = intent.radius or NS.blastRadius()
    radius = math.max(1, math.min(400, radius))

    if intent.roll then
        local rolled = NS.rollDie()
        announce(string.format("%s rolls the die for %d, %d: a %d.", nameOf(player), x, y, rolled), player)
        if rolled ~= 6 then
            announce("Not a six. The bomb stays in the bay.", player)
            return
        end
        announce("A six. Warheads are away.", player)
    end

    arm(player, x, y, radius, intent.immediate == true)
end

--- Handle one command from a player. Called directly in single player and on a
--- co-op host, and over the wire from a connected client.
---@param player IsoPlayer?
---@param sub string
---@param args table?
function Server.handle(player, sub, args)
    args = args or {}

    if sub == "sync" then
        NS.toPlayer(player, "zones", { zones = Zones.snapshot(NS.worldHours()) })
        return
    end

    if sub == "status" then
        local now = NS.worldHours()
        local lines = Zones.report(now)

        if pending ~= nil then
            local seconds = math.max(0, math.floor((pending.at - NS.realMillis()) / 1000))
            NS.tell(player, string.format("INBOUND: %d, %d in %d seconds.", pending.x, pending.y, seconds))
        end

        -- There is no cooldown, so back-to-back strikes queue up and run one
        -- after another. Say so, or a strike that has not caught up yet looks
        -- exactly like a mod that has stopped working.
        if Blast.progress ~= nil then
            local jobs, percent = Blast.progress()
            if jobs > 0 then
                NS.tell(player, string.format(
                    "Still levelling: %d job(s) queued, current one %d%% done.", jobs, percent))
            end
        end

        if #lines == 0 then
            NS.tell(player, "No strikes on record.")
        else
            NS.tell(player, "Strikes on record:")
            for _, line in ipairs(lines) do NS.tell(player, "  " .. line) end
        end
        return
    end

    -- Everything past here changes the world.
    if not allowed(player) then
        NS.tell(player, "Only admins can call a strike here.")
        return
    end

    if sub == "abort" then
        if pending == nil then
            NS.tell(player, "Nothing is inbound.")
        else
            pending = nil
            announce("The inbound strike has been aborted.", player)
        end
        return
    end

    if sub == "clear" then
        local dropped = Zones.clear()
        pushZones()
        NS.tell(player, string.format(
            "Cleared %d strike record(s). The haze is gone and no more ground will be levelled. "
            .. "Anything already destroyed stays destroyed.", dropped))
        return
    end

    if sub == "detonate" then
        if not NS.isEnabled() then
            NS.tell(player, "Nuke Strike is switched off in the sandbox options.")
            return
        end
        if args.err ~= nil then
            NS.tell(player, "Nuke Strike: " .. tostring(args.err))
            return
        end
        detonateCommand(player, args)
        return
    end
end

---@param module string
---@param command string
---@param player IsoPlayer
---@param args table?
local function onClientCommand(module, command, player, args)
    if module ~= NS.MODULE then return end
    Server.handle(player, command, args)
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(watchCountdown)
Events.EveryTenMinutes.Add(falloutTick)
