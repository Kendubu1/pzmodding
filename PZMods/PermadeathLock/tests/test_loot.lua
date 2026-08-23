-- Harness: drives PermadeathLock_Loot against a stand-in for the game's
-- procedural distribution tables.
--
-- What this is really checking is the failure that has no symptom. A loot
-- injection that matches nothing does not crash and does not warn - the item
-- simply never spawns, and a week later somebody reports "bad luck". Every
-- check here is about that being impossible to miss.

next = nil   -- Kahlua has no `next`; see MODDING-NOTES section 4

local printed = {}
local realPrint = print
function print(line)
    printed[#printed + 1] = tostring(line)
end

local function said(fragment)
    for _, line in ipairs(printed) do
        if string.find(line, fragment, 1, true) ~= nil then return true end
    end
    return false
end

SandboxVars = { PermadeathLock = {} }

local handlers = {}
Events = {}

function isServer() return true end
function isClient() return false end
function isCoopHost() return false end
function getTimestamp() return 1700000000 end
function require(_) end

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        realPrint(string.format("FAIL  %-52s got=%s want=%s", label, tostring(got), tostring(want)))
    else
        realPrint(string.format("ok    %-52s %s", label, tostring(got)))
    end
end

--- A fresh set of distribution lists, shaped the way the game's are: a flat
--- array alternating item name and weight.
local function makeLists()
    return {
        CashRegister      = { rolls = 2, items = { "Base.Money", 20, "Base.Cigarettes", 4 } },
        GasStorageCashRegister = { rolls = 1, items = { "Base.Money", 10 } },
        BankTellerCounter = { rolls = 2, items = { "Base.Money", 40 } },
        BankVault         = { rolls = 4, items = { "Base.Money", 80 } },
        -- Should be left alone.
        CrateTools        = { rolls = 3, items = { "Base.Hammer", 8 } },
        FridgeGeneric     = { rolls = 2, items = { "Base.Bread", 10 } },
    }
end

--- Load the loot file against empty event handlers, and hand back whatever it
--- registered so a test can fire it once, twice, or not at all.
---@param lists table? distribution lists to load against
---@return function[] handlers
local function load(lists)
    printed = {}
    ProceduralDistributions = { list = lists or makeLists() }
    handlers = {}
    Events = setmetatable({}, {
        __index = function(t, key)
            local list = {}
            rawset(t, key, { Add = function(fn) list[#list + 1] = fn end })
            handlers[key] = list
            return rawget(t, key)
        end,
    })
    dofile("PZMods/PermadeathLock/42/media/lua/server/PermadeathLock_Loot.lua")
    return handlers["OnPreDistributionMerge"] or {}
end

--- The usual case: load, merge once, hand back the lists.
local function run(lists)
    for _, fn in ipairs(load(lists)) do fn() end
    return ProceduralDistributions.list
end

--- The weight a list gives the Fate Token, or nil if it has none.
local function weightIn(list)
    for index = 1, #list.items, 2 do
        if list.items[index] == "Base.FateToken" then return list.items[index + 1] end
    end
end

--------------------------------------------------------------------------------
realPrint("-- off by default --")

local lists = run()
check("no token in a register", weightIn(lists.CashRegister), nil)
check("nor in a bank", weightIn(lists.BankVault), nil)
check("and it says why", said("'Fate Tokens spawn in loot' is off"), true)

--------------------------------------------------------------------------------
realPrint("\n-- switched on --")

SandboxVars.PermadeathLock.FateTokenLoot = true
lists = run()

check("tokens reach the shop till", weightIn(lists.CashRegister), 0.10)
check("and the one at the gas station", weightIn(lists.GasStorageCashRegister), 0.10)

-- The whole point of the bank bonus: likelier there, still rare.
check("banks get four times as many", weightIn(lists.BankTellerCounter), 0.40)
check("vaults too", weightIn(lists.BankVault), 0.40)
check("but a bank is still rarer than its own money", weightIn(lists.BankVault) < 80, true)

-- Nothing else in the world should have grown a Fate Token.
check("tool crates are left alone", weightIn(lists.CrateTools), nil)
check("so are fridges", weightIn(lists.FridgeGeneric), nil)

check("and the lists it touched are named", said("CashRegister@"), true)

--------------------------------------------------------------------------------
realPrint("\n-- the rarity scale --")

for level, want in pairs({ [1] = 0.05, [2] = 0.10, [3] = 0.30, [4] = 1.00 }) do
    SandboxVars.PermadeathLock.FateTokenLootRarity = level
    check("rarity " .. level .. " weights a register", weightIn(run().CashRegister), want)
end

SandboxVars.PermadeathLock.FateTokenLootRarity = 3
SandboxVars.PermadeathLock.FateTokenBankBonus = 10
check("the bank multiplier is applied", weightIn(run().BankVault), 3.0)

-- A multiplier below 1 would make banks WORSE than a corner shop, which is not
-- a setting anyone means to choose.
SandboxVars.PermadeathLock.FateTokenBankBonus = 0.1
check("a bonus below one is ignored", weightIn(run().BankVault), 0.30)
SandboxVars.PermadeathLock.FateTokenBankBonus = 4
SandboxVars.PermadeathLock.FateTokenLootRarity = 2

--------------------------------------------------------------------------------
realPrint("\n-- the failure with no symptom --")

-- Matching nothing is the one outcome that looks exactly like bad luck. It has
-- to be loud, because the alternative is somebody playing for a week and then
-- reporting that the mod does not work.
run({})
check("matching nothing is a WARNING", said("matched NO containers"), true)

--------------------------------------------------------------------------------
realPrint("\n-- switched off at the item level --")

SandboxVars.PermadeathLock.FateTokenEnabled = false
lists = run()
check("no loot when the token itself is off", weightIn(lists.CashRegister), nil)
check("and it says so", said("Fate Tokens themselves are"), true)
SandboxVars.PermadeathLock.FateTokenEnabled = true

--------------------------------------------------------------------------------
realPrint("\n-- twice is not double --")

-- A co-op Host runs two Lua states in one process. This mod has been bitten by
-- that before, and a distribution event firing twice would quietly double every
-- drop rate - which nobody notices until tokens are everywhere.
local fns = load()
fns[1]()
fns[1]()
local count = 0
for index = 1, #ProceduralDistributions.list.CashRegister.items, 2 do
    if ProceduralDistributions.list.CashRegister.items[index] == "Base.FateToken" then
        count = count + 1
    end
end
check("a second merge adds nothing", count, 1)

realPrint("")
if failures == 0 then
    realPrint("all checks passed")
else
    realPrint(failures .. " check(s) FAILED")
    os.exit(1)
end
