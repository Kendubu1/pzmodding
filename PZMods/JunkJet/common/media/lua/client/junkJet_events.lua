-- this script is not used in the mod, it's been left as a reference for testing 
-- this was used to test various actions & logic that can be triggered upon the reaload key press [R]

local junkJet = 'junkJet';

-- function JunkStart that accepts the user & firearm as parameters 
local function JunkStart(user,firearm)
    -- check if firearm is the junkjet & return true or false
    local isJunkJet = firearm:hasTag(JunkJet);
    -- gets player data
    local player = getPlayer();
    -- get player inventory
    local playerInventory = user:getInventory();

    -- loop used to iterates over all items in player inventory 
    -- if item belongs to the Junk category junkItemCount is incremented
    local junkItemCount = 0;
    for i = 0, playerInventory:getItems():size() - 1 do
        local item = playerInventory:getItems():get(i)
        if item:getDisplayCategory() == "Junk" then
            -- Increment the junk item counter.
            junkItemCount = junkItemCount + 1
        end
    end
    
    -- option to always assure weapon state is never jammed
    firearm:setJammed(false);

    -- test to check items in player inventory that can signals that the junkJet is ready
    local junkJetReady = playerInventory:contains('Base.ToyCar');
    
    -- loops over player inventory to remove a junk category item
    for i = 0, playerInventory:getItems():size() - 1 do
        local item = playerInventory:getItems():get(i)
        if item:getDisplayCategory() == "Junk" then
            -- Remove the item from the inventory.
            player:Say(item:getDisplayName())
            playerInventory:Remove(item)
            
            break
        end
    end
        
    -- if junkjet ready as true - prints text & number of junk items in inventory
    if junkJetReady then
        player:Say("Load em up!")
        player:Say(tostring(junkItemCount))
    end    
end

-- commented to avoid funtion if reload it pressed.
-- Events.OnPressReloadButton.Add(JunkStart)