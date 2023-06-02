function Fill_Mcell(items, result, player) 
    result:setCurrentAmmoCount(result:getMaxAmmo())
end

function Recipe.OnGiveXP.MetalWelding10(recipe, ingredients, result, player)
    player:getXp():AddXP(Perks.MetalWelding, 10);
end