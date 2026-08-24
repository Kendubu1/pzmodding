--[[
    Loading the ammo you just made straight into the gun in your hands.

    Shared by both builds. Build 42's craftRecipe takes an OnCreate callback
    with the same (items, result, player) signature Build 41's recipe did -
    verified against a shipping B42 mod - so one function serves both, and this
    file moved out of 41/ into common/ for that reason. While it lived in 41/,
    Build 42 players quietly lost the auto-load: the recipe had no OnCreate at
    all and the function was never even loaded.
]]

JunkJetRecipes = JunkJetRecipes or {}

--- Put a freshly crafted round into the Junk Jet, if that is what is in hand.
---@param items any the recipe's inputs
---@param result any the item produced
---@param player IsoPlayer
function JunkJetRecipes.loadAmmo(items, result, player)
    if player == nil then return end

    local weapon = player:getPrimaryHandItem()
    if weapon == nil or weapon:getType() ~= "JunkJet_Weapon" then return end
    if weapon:getAmmoType() ~= "JunkJet.JunkJet_Ammo" then return end

    weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() + 1)

    -- Taken back out of the inventory, so the round reads as having gone into
    -- the gun rather than into your pocket.
    local ammo = player:getInventory():FindAndReturn("JunkJet.JunkJet_Ammo")
    if ammo ~= nil then player:getInventory():Remove(ammo) end
end

-- Build 41's recipe format names the vanilla Recipe.OnCreate namespace, so the
-- same function is published there too. Guarded rather than assumed: the table
-- is vanilla's in Build 41 and may not exist at all in Build 42, and creating
-- an empty one is harmless either way.
Recipe = Recipe or {}
Recipe.OnCreate = Recipe.OnCreate or {}
Recipe.OnCreate.junkJetAmmoLoad = JunkJetRecipes.loadAmmo
