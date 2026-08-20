-- Harness: exercises PermadeathLock_Store against stubbed Project Zomboid globals.

local files = {}   -- in-memory stand-in for Zomboid/Lua/

function isServer() return true end
function isClient() return false end
function getTimestamp() return 1700000000 end

SandboxVars = { PermadeathLock = { Enabled = true, ExemptAdmins = true, EnforceKill = true, RestoreSkillsOnRevive = true } }

Events = setmetatable({}, { __index = function(t, k)
    local handlers = { Add = function() end, Remove = function() end }
    rawset(t, k, handlers)
    return handlers
end })

-- Perk stubs: three perks, ids matching what a snapshot would store.
local function makePerk(id)
    return {
        getId = function() return id end,
        getType = function() return "TYPE_" .. id end,
    }
end
local perkList = { makePerk("Woodwork"), makePerk("Aiming"), makePerk("Fitness") }
PerkFactory = {
    PerkList = {
        size = function() return #perkList end,
        get = function(_, i) return perkList[i + 1] end,
    },
    getPerkFromName = function(name)
        for _, perk in ipairs(perkList) do
            if perk.getId() == name then return perk end
        end
        return nil
    end,
}

function getFileWriter(name, _, append)
    if not append then files[name] = {} end
    files[name] = files[name] or {}
    local lines = files[name]
    return {
        writeln = function(_, str) lines[#lines + 1] = str end,
        write = function(_, str) lines[#lines + 1] = str end,
        close = function() end,
    }
end

function getFileReader(name, createIfNull)
    if files[name] == nil then
        if not createIfNull then return nil end
        files[name] = {}
    end
    local lines = files[name]
    local index = 0
    return {
        readLine = function() index = index + 1 return lines[index] end,
        close = function() end,
    }
end

-- A fake player whose perk levels can be read and written.
local function makePlayer(username, levels)
    local held = {}
    for k, v in pairs(levels or {}) do held[k] = v end
    return {
        getUsername = function() return username end,
        getSteamID = function() return "76561198000000001" end,
        isDead = function() return false end,
        isAccessLevel = function(_, level) return level == "nope" end,
        getPerkLevel = function(_, perkType) return held[perkType] or 0 end,
        LevelPerk = function(_, perkType) held[perkType] = (held[perkType] or 0) + 1 end,
        _levels = held,
    }
end

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")
dofile("PZMods/PermadeathLock/42/media/lua/server/PermadeathLock_Store.lua")

local Store = PermadeathLock.Store
local failures = 0

local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL  %-48s got=%s want=%s", label, tostring(got), tostring(want)))
    else
        print(string.format("ok    %-48s %s", label, tostring(got)))
    end
end

-- 1. record a death, with skills
local bob = makePlayer("Bob", { TYPE_Woodwork = 4, TYPE_Aiming = 2 })
local record = Store.record(bob, "eaten")
check("record returns a record", record ~= nil, true)
check("record is locked", Store.isLocked("Bob"), true)
check("username match is case-insensitive", Store.isLocked("bOB"), true)
check("unknown player is not locked", Store.isLocked("Alice"), false)
check("count after one death", Store.count(), 1)
check("skills snapshotted", record.skills["Woodwork"], 4)
check("zero-level perks skipped", record.skills["Fitness"], nil)

-- 2. re-recording must not overwrite the original snapshot
local bobAgain = makePlayer("Bob", {})
check("re-record is a no-op", Store.record(bobAgain, "again"), nil)
check("original reason kept", Store.get("Bob").reason, "eaten")
check("original skills kept", Store.get("Bob").skills["Woodwork"], 4)

-- 3. round-trip through the file
Store.load()
check("survives save/load", Store.isLocked("Bob"), true)
local reloaded = Store.get("Bob")
check("reason survives reload", reloaded.reason, "eaten")
check("skills survive reload", reloaded.skills["Aiming"], 2)
check("steamID survives reload", reloaded.steamID, "76561198000000001")
check("time survives reload", reloaded.time, 1700000000)

-- 4. revive: unlocked, restore queued, skills preserved
local revived = Store.revive("bob")
check("revive returns the record", revived ~= nil, true)
check("revive unlocks", Store.isLocked("Bob"), false)
check("revive queues a restore", Store.get("Bob").pendingRestore, true)
Store.load()
check("revive state survives reload", Store.get("Bob").pendingRestore, true)
check("unlocked state survives reload", Store.isLocked("Bob"), false)

-- 5. applying the restore to a fresh character
local newBob = makePlayer("Bob", { TYPE_Aiming = 5 })
local raised = Store.applySkills(newBob, Store.get("Bob").skills)
check("perks raised", raised, 1)
check("lower saved level does not demote", newBob._levels.TYPE_Aiming, 5)
check("higher saved level is restored", newBob._levels.TYPE_Woodwork, 4)
Store.finishRestore("Bob")
check("record gone after restore", Store.get("Bob"), nil)

-- 6. manual add / pardon / clear
Store.addManual("Carl", "added by admin")
check("manual add locks", Store.isLocked("carl"), true)
check("duplicate manual add refused", Store.addManual("Carl"), nil)
check("pardon removes", Store.pardon("CARL"), true)
check("pardon of unknown is false", Store.pardon("Nobody"), false)
Store.addManual("Dee")
Store.addManual("Eve")
check("count before clear", Store.count(), 2)
check("clear reports removals", Store.clear(), 2)
check("count after clear", Store.count(), 0)

-- 7. hand-edited file: bare usernames, comments, blank lines
files["PermadeathLock_deaths.txt"] = {
    "# comment",
    "",
    "Frank",
    "Gina\t\t0\tby hand",
}
Store.load()
check("bare username parsed", Store.isLocked("Frank"), true)
check("bare username defaults to locked", Store.get("Frank").locked, true)
check("partial line parsed", Store.get("Gina").reason, "by hand")
check("hand-edited count", Store.count(), 2)

-- 8. field separators in input must not corrupt a line
Store.clear()
local nasty = makePlayer("Hank", { TYPE_Woodwork = 1 })
Store.record(nasty, "died\tto\na zombie")
Store.load()
check("tabs/newlines in reason neutralised", Store.get("Hank").reason, "died to a zombie")
check("record still readable after sanitising", Store.isLocked("Hank"), true)

print("")
if failures == 0 then
    print("all checks passed")
else
    print(failures .. " check(s) FAILED")
    os.exit(1)
end
