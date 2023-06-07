-- local Shared = JunkJet.Shared;
-- local Server = JunkJet.Server;

function Recipe.OnCreate.junkJetAmmoLoad(items, result, player)
    local weapon = player:getPrimaryHandItem()
    if weapon ~= nil and weapon:getType() == "JunkJet_Weapon" then
        local ammoType = weapon:getAmmoType()
        if ammoType == "JunkJet.JunkJet_Ammo" then
            weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() + 1)
            player:Say("Junk Jet Loaded.")
        else
            player:Say("You created a Junk Jet Ammo, but it doesn't fit your current weapon.")
        end
    else
        player:Say("You created a Junk Jet Ammo, but you aren't holding the Weapon")
    end
end

-- Events.OnCreate.Add(Recipe.OnCreate.junkJetAmmoLoad)