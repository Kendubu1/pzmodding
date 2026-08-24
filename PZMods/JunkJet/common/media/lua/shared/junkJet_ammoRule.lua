--[[
    What counts as Junk Jet ammunition.

    Kept apart from the menu that uses it, and free of any game state, because
    this is the part with an actual decision in it and the part worth testing
    offline. The menu is plumbing.

    Why this exists at all: the ammo list used to be about eighty item names
    written into the crafting recipe. A recipe is a script file, read once at
    boot, so no sandbox setting could ever reach it - which is why the config
    people asked for twice was never possible in that shape. Moving the decision
    into Lua is what makes it configurable.
]]

JunkJetAmmo = JunkJetAmmo or {}

-- Never loadable, whatever the settings say: the gun itself, its own rounds,
-- and the magazine that teaches the recipes. Feeding the Junk Jet to the Junk
-- Jet is the kind of thing somebody does once and reports as a bug.
local NEVER = {
    ["JunkJet.JunkJet_Weapon"] = true,
    ["JunkJet.JunkJet_Ammo"] = true,
    ["JunkJet.JunkJet_Mag"] = true,
}

--- The two settings, read fresh each time so a mid-game change takes effect.
---@return boolean junkOnly, number maxWeight
function JunkJetAmmo.rules()
    local vars = SandboxVars and SandboxVars.JunkJet
    local junkOnly = true
    local maxWeight = 1.0

    if vars ~= nil then
        if vars.AmmoJunkOnly ~= nil then junkOnly = vars.AmmoJunkOnly == true end
        if tonumber(vars.MaxAmmoWeight) ~= nil then maxWeight = tonumber(vars.MaxAmmoWeight) end
    end
    return junkOnly, maxWeight
end

--- Whether one item can go down the hopper.
---
--- Takes the rules as arguments rather than reading them itself, so a caller
--- looping over a whole inventory reads the sandbox once instead of per item,
--- and so a test can state the rules plainly.
---@param item InventoryItem?
---@param junkOnly boolean restrict to the game's own Junk category
---@param maxWeight number heaviest item allowed; 0 or less means no limit
---@return boolean
function JunkJetAmmo.canLoad(item, junkOnly, maxWeight)
    if item == nil then return false end
    if item.getFullType == nil then return false end
    if NEVER[item:getFullType()] then return false end

    -- A container with things in it would take its contents along with it.
    if item.IsInventoryContainer ~= nil and item:IsInventoryContainer() then return false end

    if maxWeight ~= nil and maxWeight > 0 then
        local weight = 0
        if item.getActualWeight ~= nil then weight = item:getActualWeight() or 0 end
        if weight > maxWeight then return false end
    end

    if junkOnly then
        -- Checked last, and forgivingly. getDisplayCategory is the script's own
        -- word ("Junk"), but if a build ever hands back something translated
        -- this would silently reject everything - so a missing answer lets the
        -- item through rather than emptying the whole menu.
        if item.getDisplayCategory == nil then return true end
        local category = item:getDisplayCategory()
        if category == nil or category == "" then return true end
        if category ~= "Junk" then return false end
    end

    return true
end

--------------------------------------------------------------------------------
-- what is actually in the hopper
--------------------------------------------------------------------------------

-- The gun remembers WHAT was loaded, not just how much.
--
-- Ammo count alone is enough to fire, and that is all this did at first. But
-- the point of the Junk Jet is that it shoots your rubbish, and a round you can
-- watch fly and then pick up has to know it was a toy car. Recording it at load
-- time is nearly free; reconstructing it later is impossible.
--
-- Kept as one delimited string in the weapon's mod data rather than a table:
-- item mod data has to serialise into the save and sync over the network, and a
-- string does both without argument.

local LOADED = "jjLoaded"
local SEP = ";"

-- Long before the gun's own 999-round ceiling. A remembered queue is carried in
-- item mod data on every sync, so it is capped at something a magazine could
-- plausibly hold; rounds past it still fire, they just fire as anonymous junk.
JunkJetAmmo.MEMORY = 64

---@param weapon InventoryItem?
---@return string[] fullTypes, oldest first
function JunkJetAmmo.contents(weapon)
    if weapon == nil or weapon.getModData == nil then return {} end

    local data = weapon:getModData()
    local packed = data ~= nil and data[LOADED] or nil
    if packed == nil or packed == "" then return {} end

    local out = {}
    for entry in string.gmatch(packed, "[^" .. SEP .. "]+") do
        out[#out + 1] = entry
    end
    return out
end

---@param weapon InventoryItem?
---@param list string[]
local function store(weapon, list)
    if weapon == nil or weapon.getModData == nil then return end

    local data = weapon:getModData()
    if data == nil then return end
    data[LOADED] = #list > 0 and table.concat(list, SEP) or nil
end

--- Remember one more thing down the hopper.
---@param weapon InventoryItem?
---@param fullType string?
---@return boolean remembered false once the queue is full
function JunkJetAmmo.push(weapon, fullType)
    if weapon == nil or fullType == nil or fullType == "" then return false end

    local list = JunkJetAmmo.contents(weapon)
    if #list >= JunkJetAmmo.MEMORY then return false end

    list[#list + 1] = fullType
    store(weapon, list)
    return true
end

--- Take the next thing out, oldest first: what goes in first comes out first.
---@param weapon InventoryItem?
---@return string? fullType, nil once the gun is firing anonymous junk
function JunkJetAmmo.pop(weapon)
    local list = JunkJetAmmo.contents(weapon)
    if #list == 0 then return nil end

    local first = table.remove(list, 1)
    store(weapon, list)
    return first
end
