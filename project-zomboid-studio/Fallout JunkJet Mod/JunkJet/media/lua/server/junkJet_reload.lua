-- local Shared = JunkJet.Shared;
-- local Server = JunkJet.Server;

-- //script used to auto load junkjet with ammo created if holding the weapon
-- // this function runs when the recipe for creating junkjet ammo is executed
function Recipe.OnCreate.junkJetAmmoLoad(items, result, player)
    -- //get primary weapon in hand
    local weapon = player:getPrimaryHandItem()
    -- // nested condition to check if primary is junkjet & not nil
    if weapon ~= nil and weapon:getType() == "JunkJet_Weapon" then
        -- initialize variable for ammoType to check the ammotype of the weapon held
        local ammoType = weapon:getAmmoType()

        if ammoType == "JunkJet.JunkJet_Ammo" then
            -- increase the ammo count of weapon by 1
            weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() + 1)
            -- check inventory to get ammo inventory item & remove the newly created ammo to show its been loaded 
            local ammo = player:getInventory():FindAndReturn("JunkJet.JunkJet_Ammo")
            player:getInventory():Remove(ammo)

        else
            -- condition not met - ammo created but you are holding another weapoon
            --  player:Say("You created a Junk Jet Ammo, but it doesn't fit your current weapon.")
        end
    else
             -- condition not met - ammo created but you are not holding a weapoon
             --   player:Say("You created a Junk Jet Ammo, but you aren't holding the Weapon")
    end
end

