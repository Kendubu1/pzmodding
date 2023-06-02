require('NPCs/MainCreationMethods');


local function HandleMeleeUpdate(character, fool, handweapon, damage)
    local playerObj = character
    if handweapon:getType() == "ballisticfist1" and handweapon:getCurrentAmmoCount() > 0 then
        handweapon:setCurrentAmmoCount(handweapon:getCurrentAmmoCount()-1)
        playerObj:playSound("FirearmShotgun")
        if fool:isZombie() then
            fool:setStaggerBack(true)
            local oldhealth = fool:getHealth() + damage
            fool:setHealth(oldhealth)
            local newdamage = damage * 2
            local newhealth = fool:getHealth() - newdamage
            fool:setHealth(newhealth)
            --fool:applyDamageFromVehicle(damage,newdamage)
            return
        end
        fool:setBumpType("stagger")
        fool:setBumpFall(true)
        fool:setBumpFallType("pushedFront")
        --local angle = playerObj:getLastAngle()
        --local xxx =angle:getX()
        --local yyy = angle:getY()
        --local isbreak = 3
        --playerObj:Say("BANG!")
    elseif handweapon:getType() == "Shishkebab" and playerObj:getSecondaryHandItem() == "PetrolCan" then
        local Gas = playerObj:getSecondaryHandItem()
        local delta = Gas:getUsedDelta()
        if delta > 0.1 then
            playerObj:getSecondaryHandItem()
            fool:SetOnFire()
		    local newDelta = Gas:getUsedDelta() - 0.09
		    if newDelta < 0.0 then newDelta=0 end
		    Gas:setUsedDelta(newDelta)
        end
    end
end

local function HandleGunUpdate(character,handweapon)
    if handweapon:getType() == "GaussRifle"  and handweapon:getCurrentAmmoCount() > 0 then
        local tempammo = handweapon:getCurrentAmmoCount()-5
        if tempammo < 0 then tempammo = 0 end
        handweapon:setCurrentAmmoCount(tempammo)
    end
end

--Removes laser bullets from players on the server
local function EnergyCheck()
    local playerObj = getPlayer()
    if playerObj:getInventory():contains("energy") then
        while playerObj:getInventory():contains("energy") do
            playerObj:getInventory():Remove("energy")
        end
    end
end

Events.OnWeaponHitCharacter.Add(HandleMeleeUpdate)
Events.OnTick.Add(EnergyCheck)
Events.OnPlayerAttackFinished.Add(HandleGunUpdate)
