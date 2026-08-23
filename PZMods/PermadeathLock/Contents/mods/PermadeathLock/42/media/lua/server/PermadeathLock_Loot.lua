--------------------------------------------------------------------------------
-- Permadeath Lock - putting Fate Tokens in the world
--------------------------------------------------------------------------------
-- Off by default. A Fate Token undoes the only rule this mod has, so the
-- decision to let the world hand them out belongs to whoever runs the server,
-- not to us.
--
-- When it is on, tokens turn up in cash registers - the whole point of the
-- thing is that somebody, somewhere, kept a lucky coin in the till - and rather
-- more often in banks, where there is more of everything.
--
-- Containers are matched BY NAME PATTERN rather than by a hard-coded list of
-- keys. Vanilla's distribution keys are renamed and split between builds, and a
-- key that no longer exists fails silently: the item simply never spawns, and
-- there is nothing in any log to say why. Matching "register" and "bank"
-- catches the shop till, the gas station till and the bank counter alike, keeps
-- working when the game reshuffles them, and - most importantly - the boot log
-- says exactly which lists were touched, so "no tokens anywhere" is answerable
-- without guesswork.
--------------------------------------------------------------------------------

local PL = PermadeathLock
if not PL.isServerSide() then return end

require "Items/ProceduralDistributions"

-- The weight given to a token in an ordinary cash register, per rarity setting.
--
-- These are RELATIVE WEIGHTS inside one container's item list, not percentages.
-- Vanilla filler sits around 10-100, ordinary loot around 1-4, and the things
-- you remember finding around 0.1-0.5. The world's own Loot Rarity sandbox
-- setting scales all of it again on top.
local RARITY = {
    [1] = { label = "almost never", weight = 0.05 },
    [2] = { label = "very rare",    weight = 0.10 },
    [3] = { label = "rare",         weight = 0.30 },
    [4] = { label = "uncommon",     weight = 1.00 },
}
local DEFAULT_RARITY = 2

-- Matched against the lowercased distribution key. The last match wins, so a
-- list called something like "BankRegister" is treated as a bank.
local TARGETS = {
    { pattern = "register", label = "cash register" },
    { pattern = "till",     label = "till" },
    { pattern = "bank",     label = "bank",  bonus = true },
    { pattern = "vault",    label = "vault", bonus = true },
}

--- What kind of container this distribution key is, if it is one we care about.
---@param key string
---@return table? target
local function classify(key)
    local lower = string.lower(key)
    local found = nil
    for _, target in ipairs(TARGETS) do
        if string.find(lower, target.pattern, 1, true) ~= nil then found = target end
    end
    return found
end

--- Whether this item list already has a Fate Token in it.
---
--- Not paranoia. A co-op Host runs two Lua states in one process, so anything
--- that mutates shared state has to be safe against running twice - here that
--- would quietly double every drop rate, with nothing to show for it until
--- tokens were everywhere.
---@param items table flat {name, weight, name, weight, ...}
---@return boolean
local function alreadyListed(items)
    for index = 1, #items, 2 do
        if items[index] == PL.FATE_TOKEN then return true end
    end
    return false
end

local injected = false

local function addToLoot()
    if injected then return end
    injected = true

    if not PL.getOption("FateTokenLoot", false) then
        PL.lootSummary = "Fate Tokens do not spawn in the world (hand them out)."
        print("[PermadeathLock] Fate Tokens do not spawn in the world:"
            .. " 'Fate Tokens spawn in loot' is off.")
        return
    end

    if not PL.getOption("FateTokenEnabled", true) then
        PL.lootSummary = "Fate Tokens are switched off, so none are spawned."
        print("[PermadeathLock] loot spawning is on, but Fate Tokens themselves are"
            .. " switched off; nothing added.")
        return
    end

    local level = tonumber(PL.getOption("FateTokenLootRarity", DEFAULT_RARITY)) or DEFAULT_RARITY
    local rarity = RARITY[level] or RARITY[DEFAULT_RARITY]
    local bonus = tonumber(PL.getOption("FateTokenBankBonus", 4)) or 4
    if bonus < 1 then bonus = 1 end

    local lists = ProceduralDistributions and ProceduralDistributions.list
    if lists == nil then
        print("[PermadeathLock] ERROR: no ProceduralDistributions.list on this build;"
            .. " Fate Tokens cannot be added to loot.")
        PL.lootSummary = "Fate Token loot FAILED: no distribution table."
        return
    end

    local plain, rich, skipped = 0, 0, 0
    local named = {}

    for key, entry in pairs(lists) do
        local target = classify(key)
        if target ~= nil and type(entry) == "table" and type(entry.items) == "table" then
            if alreadyListed(entry.items) then
                skipped = skipped + 1
            else
                local weight = rarity.weight
                if target.bonus then weight = weight * bonus end

                entry.items[#entry.items + 1] = PL.FATE_TOKEN
                entry.items[#entry.items + 1] = weight

                if target.bonus then rich = rich + 1 else plain = plain + 1 end
                -- Every list, by name. If the tokens turn out to be in the
                -- wrong places, or in no places, this is the answer.
                if #named < 40 then named[#named + 1] = key .. "@" .. weight end
            end
        end
    end

    local total = plain + rich
    if total == 0 then
        -- Loud, because this is the failure that otherwise looks like bad luck.
        -- Somebody plays for a week, finds nothing, and has no way to tell that
        -- the mod never added the item to anything at all.
        print("[PermadeathLock] WARNING: Fate Token loot is ON but matched NO containers."
            .. " Nothing named like a register, till, bank or vault was found in"
            .. " ProceduralDistributions. Tokens will not spawn.")
        PL.lootSummary = "Fate Token loot is ON but matched no containers."
        return
    end

    PL.lootSummary = string.format(
        "Fate Tokens spawn: %s (%s in registers, %s in banks), %d container list(s).",
        rarity.label, tostring(rarity.weight), tostring(rarity.weight * bonus), total)

    print(string.format(
        "[PermadeathLock] Fate Tokens added to loot: %s. Weight %s in %d register-like"
        .. " list(s), %s in %d bank-like list(s)%s.",
        rarity.label, tostring(rarity.weight), plain,
        tostring(rarity.weight * bonus), rich,
        skipped > 0 and (", " .. skipped .. " already had one") or ""))
    print("[PermadeathLock] loot lists: " .. table.concat(named, ", ")
        .. (total > #named and (" ... and " .. (total - #named) .. " more") or ""))
end

-- The standard hook: vanilla's tables are built and not yet merged, so this is
-- the moment they can be added to. Falling back to a direct call keeps it
-- working on a build that has dropped the event, and the flag above means the
-- belt and the braces cannot both fire.
if Events ~= nil and Events.OnPreDistributionMerge ~= nil then
    Events.OnPreDistributionMerge.Add(addToLoot)
else
    print("[PermadeathLock] no OnPreDistributionMerge event; adding Fate Token loot now.")
    addToLoot()
end
