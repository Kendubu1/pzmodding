--[[
    Permadeath Lock - the death list.

    Runs wherever the server lives: a dedicated server, or the host of a co-op
    game. Records live in memory and are mirrored to a tab separated file in
    Zomboid/Lua/ so they survive a restart and can be inspected by hand.

    One line per player:
        username <tab> steamID <tab> timestamp <tab> reason <tab> skills <tab> locked <tab> pendingRestore

    'skills' is a comma separated Perk:Level list, kept so an admin can revive a
    player and hand their next character the levels the dead one had.
]]

if not PermadeathLock.isServerSide() then return end

local PL = PermadeathLock
-- Created in PermadeathLock_Shared.lua so that Server.lua, which the game loads
-- first, captures the same table. See the note there.
local Store = PL.Store

---@type table<string, table>
local records = {}
local loaded = false

local FIELD_SEP = "\t"
local HEADER = "# PermadeathLock death list - username, steamID, timestamp, reason, skills, locked, pendingRestore"

--------------------------------------------------------------------------------
-- text helpers
--------------------------------------------------------------------------------

--- Split on a literal separator, keeping empty fields.
---@param str string
---@param sep string
---@return string[]
local function split(str, sep)
    local out = {}
    local start = 1
    while true do
        local index = string.find(str, sep, start, true)
        if index == nil then
            out[#out + 1] = string.sub(str, start)
            return out
        end
        out[#out + 1] = string.sub(str, start, index - 1)
        start = index + #sep
    end
end

--- Strip anything that would break the one-record-per-line format.
---@param value any
---@return string
local function clean(value)
    if value == nil then return "" end
    local text = tostring(value)
    text = text:gsub("[\t\r\n]", " ")
    return text
end

--------------------------------------------------------------------------------
-- skills
--------------------------------------------------------------------------------

--- Every perk, indexed by its id AND its display name.
---
--- This exists because the two are not the same string and the mod used both.
--- A snapshot stores perk:getId() - "Woodwork", "Blunt" - while the restore
--- looked the perk back up with PerkFactory.getPerkFromName, which matches the
--- *display* name - "Carpentry", "Long Blunt". Every perk whose two names
--- differ silently resolved to nil, so most of a character's skills were never
--- given back and the count reported to the player was far too low.
---
--- Indexing both keys also means death lists written by older versions, or
--- edited by hand with display names in them, still load.
---@type table<string, any>?
local perkIndex = nil

---@return table<string, any>
local function perksByKey()
    if perkIndex ~= nil then return perkIndex end

    local index = {}
    local found = 0

    local perks = PerkFactory and PerkFactory.PerkList
    if perks == nil then return index end

    for i = 0, perks:size() - 1 do
        local perk = perks:get(i)
        if perk ~= nil then
            index[tostring(perk:getId())] = perk
            found = found + 1
            -- getName is absent on some stubs and older builds; only index it
            -- when it is really there, and never let it shadow an id.
            if perk.getName ~= nil then
                local name = perk:getName()
                if name ~= nil and index[tostring(name)] == nil then
                    index[tostring(name)] = perk
                end
            end
        end
    end

    -- Only cache once the perk list is actually populated. Called before
    -- PerkFactory.init() this would otherwise cache an empty table forever.
    --
    -- Counted in the loop rather than asked afterwards with next(). Kahlua, the
    -- Lua implementation the game runs, does not provide `next` - calling it
    -- threw on every sweep, which aborted the restore before the record was
    -- cleared, so the player got no skills back and the crash repeated forever.
    if found > 0 then perkIndex = index end
    return index
end

--- Snapshot every perk the character has at least one level in.
---@param player IsoPlayer
---@return table<string, integer>
local function snapshotSkills(player)
    local skills = {}
    local perks = PerkFactory and PerkFactory.PerkList
    if perks == nil then return skills end

    for i = 0, perks:size() - 1 do
        local perk = perks:get(i)
        if perk ~= nil then
            local perkType = perk:getType()
            local level = player:getPerkLevel(perkType)
            if level ~= nil and level > 0 then
                skills[tostring(perk:getId())] = level
            end
        end
    end
    return skills
end

---@param skills table<string, integer>
---@return string
local function serialiseSkills(skills)
    local parts = {}
    for name, level in pairs(skills or {}) do
        parts[#parts + 1] = clean(name) .. ":" .. tostring(level)
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

---@param text string
---@return table<string, integer>
local function deserialiseSkills(text)
    local skills = {}
    if text == nil or text == "" then return skills end
    for entry in string.gmatch(text, "[^,]+") do
        local name, level = string.match(entry, "^(.-):(%-?%d+)$")
        if name ~= nil and name ~= "" then
            skills[name] = tonumber(level)
        end
    end
    return skills
end

--- Put one perk at a level.
---
--- setPerkLevelDebug does it in a single call. The alternative - LevelPerk once
--- per level - runs the whole level-up cascade every time: XP maths, the sound,
--- the on-screen flash, a character-screen refresh. A restore is a dozen perks
--- at once, so that is easily forty of those cascades inside one frame on a
--- character that has just been handed its old life back. Kept as the fallback
--- for a build that does not expose the direct setter.
---@param player IsoPlayer
---@param perkType any
---@param current integer
---@param level integer
local function setPerkLevel(player, perkType, current, level)
    if player.setPerkLevelDebug ~= nil then
        player:setPerkLevelDebug(perkType, level)
        return
    end

    for _ = current + 1, level do
        player:LevelPerk(perkType)
    end
end

--- Give a character the levels from a snapshot. Levels already held are kept,
--- so this never demotes anyone.
---
--- The count returned is every perk the character now holds at the recorded
--- level, not just the ones this call had to raise. A player told "2 skills
--- restored" when their dead character had eleven reasonably concludes the mod
--- lost the other nine.
---@param player IsoPlayer
---@param skills table<string, integer>
---@return integer restored perks now held at the recorded level
---@return string[] missing perk keys that could not be resolved
function Store.applySkills(player, skills)
    local restored, missing = 0, {}
    if player == nil or skills == nil then return restored, missing end

    local index = perksByKey()

    for name, level in pairs(skills) do
        local perk = index[name]
        if perk == nil or level == nil then
            missing[#missing + 1] = tostring(name)
        else
            local perkType = perk:getType()
            local current = player:getPerkLevel(perkType) or 0
            if current < level then
                setPerkLevel(player, perkType, current, level)
            end
            restored = restored + 1
        end
    end

    table.sort(missing)
    return restored, missing
end

---------------------------------------------------------------
-- persistence
--------------------------------------------------------------------------------

---@param record table
---@return string
local function serialise(record)
    local reason = clean(record.reason)
    local skills = serialiseSkills(record.skills)
    return table.concat({
        clean(record.username),
        clean(record.steamID),
        tostring(record.time or 0),
        reason,
        skills,
        record.locked and "1" or "0",
        record.pendingRestore and "1" or "0",
    }, FIELD_SEP)
end

---@param line string
---@return table? record
local function deserialise(line)
    local fields = split(line, FIELD_SEP)
    local username = fields[1]
    if username == nil or username == "" then return nil end

    return {
        username = username,
        steamID = fields[2] or "",
        time = tonumber(fields[3]) or 0,
        reason = fields[4] or "",
        skills = deserialiseSkills(fields[5]),
        -- Older or hand-written files may omit the flags; a listed player is
        -- locked unless the file says otherwise.
        locked = (fields[6] or "1") ~= "0",
        pendingRestore = (fields[7] or "0") == "1",
    }
end

function Store.save()
    local writer = getFileWriter(PL.DEATH_FILE, true, false)
    if writer == nil then
        print("[PermadeathLock] ERROR: could not open " .. PL.DEATH_FILE .. " for writing.")
        return
    end

    writer:writeln(HEADER)
    for _, record in pairs(records) do
        writer:writeln(serialise(record))
    end
    writer:close()
end

function Store.load()
    records = {}

    local reader = getFileReader(PL.DEATH_FILE, true)
    if reader == nil then
        loaded = true
        return
    end

    local line = reader:readLine()
    while line ~= nil do
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            local record = deserialise(line)
            local key = record and PL.key(record.username)
            if key ~= nil then
                records[key] = record
            end
        end
        line = reader:readLine()
    end
    reader:close()

    loaded = true
    print("[PermadeathLock] Loaded " .. Store.count() .. " death record(s) from " .. PL.DEATH_FILE .. ".")
end

local function ensureLoaded()
    if not loaded then Store.load() end
end

--------------------------------------------------------------------------------
-- queries
--------------------------------------------------------------------------------

---@param username string?
---@return table? record
function Store.get(username)
    ensureLoaded()
    local key = PL.key(username)
    if key == nil then return nil end
    return records[key]
end

--- True when this player is barred from playing a new character.
---@param username string?
---@return boolean
function Store.isLocked(username)
    local record = Store.get(username)
    return record ~= nil and record.locked == true
end

---@return integer
function Store.count()
    ensureLoaded()
    local total = 0
    for _ in pairs(records) do total = total + 1 end
    return total
end

--- All records, sorted by death time (oldest first).
---@return table[]
function Store.all()
    ensureLoaded()
    local out = {}
    for _, record in pairs(records) do out[#out + 1] = record end
    table.sort(out, function(a, b) return (a.time or 0) < (b.time or 0) end)
    return out
end

--------------------------------------------------------------------------------
-- mutations
--------------------------------------------------------------------------------

--- Add a death. Re-recording an existing death is a no-op, so the original
--- timestamp and skill snapshot survive repeated sweeps over a dead body.
---
--- A 'saved' death (the player spent a Fate Token) is recorded unlocked with a
--- restore already queued: they are never blocked, and their next character
--- collects the skills automatically.
---@param player IsoPlayer
---@param reason string?
---@param saved boolean? true when a Fate Token was spent
---@return table? record nil when nothing was recorded
function Store.record(player, reason, saved)
    ensureLoaded()
    if player == nil then return nil end

    local username = player:getUsername()
    local key = PL.key(username)
    if key == nil then return nil end
    if records[key] ~= nil then return nil end

    -- Recorded for identification only; matching is always by username. Wrapped
    -- because the call is unavailable on servers running without Steam.
    local steamID = ""
    local ok, value = pcall(function() return player:getSteamID() end)
    if ok and value ~= nil then steamID = tostring(value) end

    local record = {
        username = username,
        steamID = steamID,
        time = getTimestamp(),
        reason = reason or "died",
        skills = snapshotSkills(player),
        locked = not saved,
        pendingRestore = saved == true,
    }
    records[key] = record
    Store.save()
    return record
end

--- Mark a player as dead without them being online. Used by /permadeath add.
---@param username string
---@param reason string?
---@return table? record
function Store.addManual(username, reason)
    ensureLoaded()
    local key = PL.key(username)
    if key == nil or records[key] ~= nil then return nil end

    records[key] = {
        username = username,
        steamID = "",
        time = getTimestamp(),
        reason = reason or "added by admin",
        skills = {},
        locked = true,
        pendingRestore = false,
    }
    Store.save()
    return records[key]
end

--- Forget a player entirely. They may rejoin, and start from scratch.
---@param username string
---@return boolean removed
function Store.pardon(username)
    ensureLoaded()
    local key = PL.key(username)
    if key == nil or records[key] == nil then return false end

    records[key] = nil
    Store.save()
    return true
end

--- Unlock a player and queue their skills to be handed to their next character.
---@param username string
---@return table? record nil when they were not on the list
function Store.revive(username)
    ensureLoaded()
    local key = PL.key(username)
    local record = key and records[key]
    if record == nil then return nil end

    record.locked = false
    record.pendingRestore = true
    Store.save()
    return record
end

--- Called once the queued skills have been applied to a live character.
---@param username string
function Store.finishRestore(username)
    ensureLoaded()
    local key = PL.key(username)
    if key == nil or records[key] == nil then return end

    records[key] = nil
    Store.save()
end

---@return integer count removed
function Store.clear()
    ensureLoaded()
    local removed = Store.count()
    records = {}
    Store.save()
    return removed
end

--------------------------------------------------------------------------------
-- load as early as the game allows
--------------------------------------------------------------------------------

Events.OnServerStarted.Add(Store.load)
Events.OnInitGlobalModData.Add(ensureLoaded)
