local junkJet = 'junkJet';

local function JunkStart(user,firearm)
    local attacker = user;
    local isJunkJet = firearm:hasTag(JunkJet);
    local player = getPlayer();
    local playerInventory = user:getInventory();

    local junkItemCount = 0;
    for i = 0, playerInventory:getItems():size() - 1 do
        local item = playerInventory:getItems():get(i)
        if item:getDisplayCategory() == "Junk" then
            -- Increment the junk item counter.
            junkItemCount = junkItemCount + 1
        end
    end
    -- if not isJunkJet then
    --     print('JunkJet');
    -- end
    
    firearm:setJammed(false);
    local junkJetReady = playerInventory:contains('Base.ToyCar');
    -- for i = 0, playerInventory:getItems():size() - 1 do
    --     local item = playerInventory:getItems():get(i)
    --     if item:getDisplayCategory() == "Junk" then
    --         -- Remove the item from the inventory.
    --         player:Say(item:getDisplayName())
    --         playerInventory:Remove(item)
            
    --         break
    --     end
    -- end
        

    if junkJetReady then
        player:Say("Load em up!")
        player:Say(tostring(junkItemCount))
    end    
end

-- Events.OnPressReloadButton.Add(JunkStart)