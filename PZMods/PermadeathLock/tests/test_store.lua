-- Harness: exercises PermadeathLock_Store against stubbed Project Zomboid globals.

local files = {}   -- in-memory stand-in for Zomboid/Lua/

function isServer() return true end
function isClient() return false end
function getTimestamp() return 1700000000 end

-- Kahlua, the Lua implementation Project Zomboid runs, does not provide every
-- Lua 5.1 global. `next` in particular is missing, and a call to it threw on
-- every sweep. Removing them here makes that class of mistake a failing test
-- rather than a server log full of stack traces. pairs/ipairs are unaffected:
-- Lua 5.1 implements them natively rather than through the global.
next = nil

SandboxVars = { PermadeathLock = { Enabled = true, ExemptAdmins = true, EnforceKill = true, RestoreSkillsOnRevive = true } }

Events = setmetatable({}, { __index = function(t, k)
    local handlers = { Add = function() end, Remove = function() end }
    rawset(t, k, handlers)
    return handlers
end })

-- Perk stubs. The id and the display name are DELIBERATELY different for
-- Woodwork, because they are in the real game ("Woodwork" / "Carpentry") and
-- the mod once snapshotted one and looked the other up. getPerkFromName matches
-- the display name only, exactly like PerkFactory does, so a restore that goes
-- through it finds nothing for that perk.
local function makePerk(id, displayName)
    return {
        getId = function() return id end,
        getName = function() return displayName or id end,
        getType = function() return "TYPE_" .. id end,
        -- A flat curve is enough: the restore only needs the difference between
        -- where the character is and where the snapshot says they were.
        getTotalXpForLevel = function(_, level) return level * 100 end,
    }
end
local perkList = {
    makePerk("Woodwork", "Carpentry"),
    makePerk("Aiming", "Aiming"),
    makePerk("Fitness", "Fitness"),
}
PerkFactory = {
    PerkList = {
        size = function() return #perkList end,
        get = function(_, i) return perkList[i + 1] end,
    },
    getPerkFromName = function(name)
        for _, perk in ipairs(perkList) do
            if perk.getName() == name then return perk end
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

    -- The XP object the restore prefers, mirroring how the game itself levels a
    -- character and how vanilla /addxp does it. Crossing a hundred points is a
    -- level, matching the curve on the perk stubs above.
    local xp = { _points = {}, _order = {} }
    function xp:getXP(perkType) return self._points[perkType] or 0 end
    function xp:AddXPNoMultiplier(perkType, amount)
        self._points[perkType] = (self._points[perkType] or 0) + amount
        held[perkType] = math.floor(self._points[perkType] / 100)
        self._order[#self._order + 1] = perkType
    end

    return {
        _xp = xp,
        getXp = function() return xp end,
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
--
-- REGRESSION: the physical perks go last. Restoring a character was killing it
-- outright - only ever on the two paths that restore, never on a plain death -
-- and Fitness and Strength are what the body's condition is computed from. Last
-- means everything else has already landed, and the per-perk log names whatever
-- it stopped at.
local newBob = makePlayer("Bob", { TYPE_Aiming = 5 })
local restored, missing = Store.applySkills(newBob, Store.get("Bob").skills)
-- REGRESSION: Woodwork is stored by id and its display name is "Carpentry".
-- Resolving the snapshot through getPerkFromName found nothing for it, so the
-- level was never given back.
check("perk stored by id is restored", newBob._levels.TYPE_Woodwork, 4)
check("lower saved level does not demote", newBob._levels.TYPE_Aiming, 5)
-- The count is every perk the character now holds at the recorded level, not
-- just the ones that had to be raised: Aiming was already high enough and still
-- counts, because it was restored as promised.
check("count includes perks already high enough", restored, 2)
check("nothing reported missing", #missing, 0)
Store.finishRestore("Bob")
check("record gone after restore", Store.get("Bob"), nil)

-- 5b. a snapshot naming a perk the game no longer has is reported, not silently
-- dropped
local ghost = makePlayer("Ghost", {})
local ghostRestored, ghostMissing = Store.applySkills(ghost, { Aiming = 3, Sorcery = 4 })
check("known perk still restored", ghost._levels.TYPE_Aiming, 3)
check("unknown perk not counted as restored", ghostRestored, 1)
check("unknown perk reported missing", ghostMissing[1], "Sorcery")

-- 5c. display names in a hand-edited file still resolve
local handEdited = makePlayer("Hand", {})
Store.applySkills(handEdited, { Carpentry = 6 })
check("display name resolves too", handEdited._levels.TYPE_Woodwork, 6)

-- 5d. the physical perks are restored last, whatever order the snapshot is in
local ordered = makePlayer("Ordered", {})
Store.applySkills(ordered, { Fitness = 3, Woodwork = 2, Aiming = 1 })
local touched = ordered._xp._order
check("everything is restored", #touched, 3)
check("and Fitness comes last", touched[#touched], "TYPE_Fitness")

-- 5e. XP is the route taken, not the level-up cascade
check("levels come from XP", ordered._levels.TYPE_Woodwork, 2)
check("with the right amount of it", ordered._xp:getXP("TYPE_Woodwork"), 200)

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
