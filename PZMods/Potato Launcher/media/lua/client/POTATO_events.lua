local POTATO_LAUNCHER = 'PotatoLauncher';

local function OnCheckPotatoLauncher(player, firearm)
    local attacker = player;
    local isPotatoLauncher = firearm:hasTag(POTATO_LAUNCHER);
    -- This function is called when any weapon is reloaded
    -- I need to continue only if user is reloading Potato Launcher
    if not isPotatoLauncher then
        print(getText('IGUI_POTATO_continue'));
        return true;
    end

    local inv = player:getInventory();

    -- Clear any jam status
    firearm:setJammed(false);

    -- If Potato Launcher is already charged don't waste below items
    local isCharged = firearm:isRoundChambered();
    if isCharged then
        return true;
    end

    -- Prevent reload if user doesn't have Potato Launcher Fuel
    local isFuelAvailable = inv:contains('PotatoLauncher.POTATO_Fuel');
    if not isFuelAvailable then
        -- Prevent reloading by jamming the weapon
        firearm:setJammed(true);
        player:Say(getText('IGUI_POTATO_needFuel'));
        return false;
    end
    
    -- Prevent reload if user doesn't have a Battery
    local isBatteryAvailable = inv:contains('Base.Battery');
    if not isBatteryAvailable then
        -- Prevent reloading by jamming the weapon
        firearm:setJammed(true);
        player:Say(getText('IGUI_POTATO_needBattery'));
        return false;
    end

    -- Prevent reload if user doesn't have a Potato
    local isPotatoAvailable = inv:contains('farming.Potato');
    if isPotatoAvailable then
        local fuel = inv:FindAndReturn('PotatoLauncher.POTATO_Fuel');
        local battery = inv:FindAndReturn('Base.Battery');
        fuel:Use();
        battery:Use();
    end
end

Events.OnPressReloadButton.Add(OnCheckPotatoLauncher)