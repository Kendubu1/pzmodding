--[[
    "Load into Junk Jet" on the inventory right-click menu.

    The plumbing for junkJet_ammoRule.lua. Everything with a decision in it
    lives there; this finds the gun, offers the entry, and moves the item.

    Done the way vanilla reloads a firearm - on the client, against the
    player's own inventory and their own weapon - rather than routed through
    the server. Vanilla's own reload does the same, and the ammo count lives on
    the weapon item, which syncs.

    The whole builder is wrapped: an error raised while the game is building a
    context menu takes the ENTIRE menu down, not just this entry. Doors,
    corpses, everything. That is not a hypothetical - it happened to a
    neighbouring mod in this repo.
]]

require "junkJet_ammoRule"

local ADD_ONE = 1

--- The player's Junk Jet, the one in their hands for preference.
---@param player IsoPlayer
---@return InventoryItem? weapon
local function findJunkJet(player)
    local held = player:getPrimaryHandItem()
    if held ~= nil and held.getFullType ~= nil
        and held:getFullType() == "JunkJet.JunkJet_Weapon" then
        return held
    end

    local inventory = player:getInventory()
    if inventory == nil then return nil end

    local found = inventory:FindAndReturn("JunkJet.JunkJet_Weapon")
    if found ~= nil then return found end
    return nil
end

--- Stuff one item down the hopper.
---@param player IsoPlayer
---@param weapon InventoryItem
---@param item InventoryItem
local function loadOne(player, weapon, item)
    local inventory = player:getInventory()
    if inventory == nil then return end

    -- Read before the item is destroyed, obviously, but worth saying: this is
    -- the only moment the gun can learn what it is loaded with. Afterwards the
    -- item is gone and a round is just a number.
    local fullType = item:getFullType()

    -- Removed first. If the ammo count were raised first and the removal then
    -- failed, the player would have gained a round and kept the junk.
    inventory:Remove(item)

    weapon:setCurrentAmmoCount((weapon:getCurrentAmmoCount() or 0) + ADD_ONE)
    JunkJetAmmo.push(weapon, fullType)

    -- The count lives on the weapon item, so the change has to be broadcast or
    -- only this machine knows about it.
    if syncItemFields ~= nil then syncItemFields(player, weapon) end
end

---@param player IsoPlayer
---@param weapon InventoryItem
---@param items InventoryItem[]
local function loadAll(player, weapon, items)
    for _, item in ipairs(items) do
        loadOne(player, weapon, item)
    end
end

--- Everything selected that the rules allow, deduplicated.
---
--- The menu hands over a mixed list: some entries are items, some are tables of
--- identical stacked items. Both shapes have to be unpacked or a stack of
--- fifteen tin cans offers one round.
---@param selected table
---@return InventoryItem[]
local function loadable(selected)
    local junkOnly, maxWeight = JunkJetAmmo.rules()

    local out = {}
    for _, entry in ipairs(selected) do
        if entry ~= nil and entry.items ~= nil then
            for i = 1, #entry.items do
                local item = entry.items[i]
                if JunkJetAmmo.canLoad(item, junkOnly, maxWeight) then out[#out + 1] = item end
            end
        elseif JunkJetAmmo.canLoad(entry, junkOnly, maxWeight) then
            out[#out + 1] = entry
        end
    end
    return out
end

---@param playerIndex integer
---@param context ISContextMenu
---@param selected table
local function buildMenu(playerIndex, context, selected)
    local player = getSpecificPlayer(playerIndex)
    if player == nil then return end

    local weapon = findJunkJet(player)
    if weapon == nil then return end

    local items = loadable(selected)
    if #items == 0 then return end

    local label = getText("ContextMenu_JunkJet_Load")
    if #items > 1 then label = label .. " (" .. #items .. ")" end

    context:addOption(label, player, function() loadAll(player, weapon, items) end)
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerIndex, context, selected)
    local ok, err = pcall(buildMenu, playerIndex, context, selected)
    if not ok then
        print("[JunkJet] ERROR building the load menu: " .. tostring(err))
    end
end)
