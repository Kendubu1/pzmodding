--------------------------------------------------------------------------------
-- Permadeath Lock - the bind registry
--------------------------------------------------------------------------------
-- Every place a Fate Token has been bound to, written down independently of the
-- token itself.
--
-- The binding lives on the item, which is right: it travels with the token when
-- it changes hands, and two tokens in one pocket keep their own places. But an
-- item is a thing that can be dropped in a bag, left in a crate, or carried off
-- by someone who then logs out for a month, and the game gives no way at all to
-- go looking for it. There is no index of every item in the world; a search
-- would have to walk the loaded squares, which covers only the corner of the
-- map somebody happens to be standing in.
--
-- So this registry does the one honest thing that IS possible: it remembers the
-- COORDINATE, who bound it, and when. An admin can always recover the place,
-- even when the token holding it has been lost - which is the thing people
-- actually ask for. It deliberately does not claim to know where the item is.
-- What it can say, for tokens currently in an online player's hands, is who is
-- holding which; anything else is honestly reported as "not seen".
--------------------------------------------------------------------------------

local PL = PermadeathLock
local Binds = PL.Binds

local FIELD_SEP = "\t"
local HEADER = "# id\tx\ty\tz\tboundBy\ttime"

---@type table<number, table>
local entries = {}

-- Registry numbers are handed out in order and never reused, so a number in a
-- log line always means the same token. Loading takes the highest it finds.
local nextId = 1

local loaded = false

--------------------------------------------------------------------------------
-- persistence
--------------------------------------------------------------------------------

--- Strip anything that would break the one-record-per-line format.
---@param value any
---@return string
local function clean(value)
    local text = tostring(value or "")
    text = string.gsub(text, "[\t\r\n]", " ")
    return text
end

---@param text string
---@param sep string
---@return string[]
local function split(text, sep)
    local out = {}
    local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
    for field in string.gmatch(text .. sep, pattern) do
        out[#out + 1] = field
    end
    -- gmatch on the padded string yields one trailing empty field.
    out[#out] = nil
    return out
end

function Binds.save()
    local writer = getFileWriter(PL.BIND_FILE, true, false)
    if writer == nil then
        print("[PermadeathLock] ERROR: could not open " .. PL.BIND_FILE .. " for writing.")
        return
    end

    writer:writeln(HEADER)
    for id, entry in pairs(entries) do
        writer:writeln(table.concat({
            tostring(id),
            tostring(entry.x),
            tostring(entry.y),
            tostring(entry.z),
            clean(entry.boundBy),
            tostring(entry.time or 0),
        }, FIELD_SEP))
    end
    writer:close()
end

function Binds.load()
    entries = {}
    nextId = 1

    local reader = getFileReader(PL.BIND_FILE, true)
    if reader == nil then
        loaded = true
        return
    end

    local count = 0
    local line = reader:readLine()
    while line ~= nil do
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            local fields = split(line, FIELD_SEP)
            local id = tonumber(fields[1])
            local x, y = tonumber(fields[2]), tonumber(fields[3])
            if id ~= nil and x ~= nil and y ~= nil then
                entries[id] = {
                    id = id,
                    x = x,
                    y = y,
                    z = tonumber(fields[4]) or 0,
                    boundBy = fields[5] or "",
                    time = tonumber(fields[6]) or 0,
                }
                count = count + 1
                if id >= nextId then nextId = id + 1 end
            end
        end
        line = reader:readLine()
    end
    reader:close()

    loaded = true
    print("[PermadeathLock] Loaded " .. count .. " token bind(s) from " .. PL.BIND_FILE .. ".")
end

local function ensureLoaded()
    if not loaded then Binds.load() end
end

--------------------------------------------------------------------------------
-- the registry
--------------------------------------------------------------------------------

--- The next unused registry number, reserved by the act of asking for it.
---@return number
function Binds.claimId()
    ensureLoaded()

    local id = nextId
    nextId = id + 1
    return id
end

--- Write down where a token has been bound.
---@param id number
---@param x number
---@param y number
---@param z number?
---@param boundBy string?
function Binds.set(id, x, y, z, boundBy)
    ensureLoaded()
    if id == nil then return end

    entries[id] = {
        id = id,
        x = math.floor(x),
        y = math.floor(y),
        z = math.floor(z or 0),
        boundBy = boundBy or "",
        time = getTimestamp(),
    }
    if id >= nextId then nextId = id + 1 end
    Binds.save()
end

--- Forget one bind. Called when the token is spent: the place has been used,
--- and leaving it on a list of recoverable coordinates would be a lie.
---@param id number?
function Binds.forget(id)
    ensureLoaded()
    if id == nil or entries[id] == nil then return end

    entries[id] = nil
    Binds.save()
end

---@param id number?
---@return table? entry
function Binds.get(id)
    ensureLoaded()
    if id == nil then return nil end
    return entries[id]
end

---@return integer
function Binds.count()
    ensureLoaded()

    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return count
end

--- Every bind on record, oldest first, each one told who is holding its token
--- if that can be worked out right now.
---
--- "Held by" is only ever answered for players who are online, because that is
--- the only inventory the server can read. A token in an offline player's
--- pocket, in a crate, or on the floor all look the same from here, and are all
--- reported the same way: not seen.
---@return table[] entries
function Binds.all()
    ensureLoaded()

    local holder = {}
    local players = getOnlinePlayers()
    if players ~= nil then
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player ~= nil then
                for _, token in ipairs(PL.findTokens(player)) do
                    local id = PL.getTokenId(token)
                    if id ~= nil then holder[id] = player:getUsername() end
                end
            end
        end
    end

    local out = {}
    for id, entry in pairs(entries) do
        out[#out + 1] = {
            id = id,
            x = entry.x,
            y = entry.y,
            z = entry.z,
            boundBy = entry.boundBy,
            time = entry.time,
            heldBy = holder[id],
        }
    end

    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Binds.clear()
    ensureLoaded()

    entries = {}
    Binds.save()
end
