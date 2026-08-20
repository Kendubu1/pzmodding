--[[
    Permadeath Lock - the death list.

    Server side only. Records live in memory and are mirrored to a tab separated
    file in Zomboid/Lua/ so they survive a restart and can be inspected by hand.

    One line per player:
        username <tab> steamID <tab> timestamp <tab> reason <tab> skills <tab> locked <tab> pendingRestore

    'skills' is a comma separated Perk:Level list, kept so an admin can revive a
    player and hand their next character the levels the dead one had.
]]

if not isServer() then return end

local PL = PermadeathLock
PL.Store = PL.Store or {}
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

--- Give a character the levels from a snapshot. Levels already held are kept,
--- so this never demotes anyone.
---@param player IsoPlayer
---@param skills table<string, integer>
---@return integer count of perks raised
function Store.applySkills(player, skills)
    local raised = 0
    if player == nil or skills == nil then return raised end

    for name, level in pairs(skills) do
        local perk = PerkFactory.getPerkFromName(name)
        if perk ~= nil and level ~= nil then
            local perkType = perk:getType()
            local current = player:getPerkLevel(perkType) or 0
            if current < level then
                for _ = current + 1, level do
                    player:LevelPerk(perkType)
                end
                raised = raised + 1
            end
        end
    end
    return raised
end

--------------------------------------------------------------------------------
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
