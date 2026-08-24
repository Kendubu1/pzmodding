-- Harness: what the Junk Jet will and will not swallow.
--
-- The rule is the whole point of the ammo rework - it replaced about eighty
-- item names hardcoded into a crafting recipe - so it is the part that gets
-- tested. It is deliberately free of game state so it can be.

next = nil   -- Kahlua has no `next`; see MODDING-NOTES section 4

SandboxVars = { JunkJet = {} }
dofile("PZMods/JunkJet/common/media/lua/shared/junkJet_ammoRule.lua")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        io.write(string.format("FAIL  %-52s got=%s want=%s\n", label, tostring(got), tostring(want)))
    else
        io.write(string.format("ok    %-52s %s\n", label, tostring(got)))
    end
end

--- opts: weight, category, container
local function item(fullType, opts)
    opts = opts or {}
    return {
        getFullType = function() return fullType end,
        getActualWeight = function() return opts.weight or 0.1 end,
        getDisplayCategory = function() return opts.category end,
        IsInventoryContainer = function() return opts.container == true end,
    }
end

local JUNK_ONLY, ANYTHING = true, false
local NO_LIMIT = 0

--------------------------------------------------------------------------------
io.write("-- the default: junk, and nothing heavy --\n")

check("a toy car goes in", JunkJetAmmo.canLoad(
    item("Base.ToyCar", { category = "Junk", weight = 0.1 }), JUNK_ONLY, 1.0), true)
check("a tin of beans does not", JunkJetAmmo.canLoad(
    item("Base.TinnedBeans", { category = "Food", weight = 0.4 }), JUNK_ONLY, 1.0), false)
check("nor does a heavy piece of junk", JunkJetAmmo.canLoad(
    item("Base.Anvil", { category = "Junk", weight = 8 }), JUNK_ONLY, 1.0), false)

--------------------------------------------------------------------------------
io.write("\n-- loosening the rules --\n")

-- The setting people actually asked for: fire anything.
check("with junk-only off, the beans go in", JunkJetAmmo.canLoad(
    item("Base.TinnedBeans", { category = "Food", weight = 0.4 }), ANYTHING, 1.0), true)
check("the weight limit still applies", JunkJetAmmo.canLoad(
    item("Base.Sledgehammer", { category = "Weapon", weight = 6 }), ANYTHING, 1.0), false)
check("and with no limit, the sledgehammer goes in too", JunkJetAmmo.canLoad(
    item("Base.Sledgehammer", { category = "Weapon", weight = 6 }), ANYTHING, NO_LIMIT), true)

--------------------------------------------------------------------------------
io.write("\n-- what must never load, whatever the settings --\n")

for _, id in ipairs({ "JunkJet.JunkJet_Weapon", "JunkJet.JunkJet_Ammo", "JunkJet.JunkJet_Mag" }) do
    check(id .. " is refused", JunkJetAmmo.canLoad(
        item(id, { category = "Junk" }), ANYTHING, NO_LIMIT), false)
end

-- A bag would take everything inside it along for the ride.
check("a bag with contents is refused", JunkJetAmmo.canLoad(
    item("Base.Bag_Satchel", { category = "Junk", container = true }), ANYTHING, NO_LIMIT), false)
check("and nil is not a crash", JunkJetAmmo.canLoad(nil, JUNK_ONLY, 1.0), false)

--------------------------------------------------------------------------------
io.write("\n-- a category the build will not tell us --\n")

-- getDisplayCategory returning nothing must not empty the entire menu: better
-- to let an item through than to make the feature look broken.
check("no category answer lets it through", JunkJetAmmo.canLoad(
    item("Base.Mystery", { category = nil }), JUNK_ONLY, 1.0), true)

--------------------------------------------------------------------------------
io.write("\n-- reading the sandbox --\n")

SandboxVars.JunkJet = {}
local junkOnly, maxWeight = JunkJetAmmo.rules()
check("defaults to junk only", junkOnly, true)
check("and a 1.0 weight limit", maxWeight, 1.0)

SandboxVars.JunkJet = { AmmoJunkOnly = false, MaxAmmoWeight = 3.5 }
junkOnly, maxWeight = JunkJetAmmo.rules()
check("a changed setting is picked up", junkOnly, false)
check("and so is the weight", maxWeight, 3.5)

-- Read fresh every call, so an admin changing it mid-game takes effect without
-- a restart.
SandboxVars.JunkJet.MaxAmmoWeight = 0
check("and again on the next call", select(2, JunkJetAmmo.rules()), 0)

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
