local Shared = MandelaBowAndArrow.Shared;
local Server = MandelaBowAndArrow.Server;

Server.Textures = {};
--Server.Textures.BowTexture = getTexture("media/textures/Item_MBAOMandelaBow.png"); -?

function Server.loadTextures()
    getTexture("profession_archer.png");
end

Events.OnGameBoot.Add(Server.loadTextures);

--These functions are run when certain recipes are completed.
Server.Recipe = {};
--[[
function Server.Recipe.OnSnapArrowShaftWooden(items, result, player, selectedItem)
	local factoryItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaAttachmentShaftWood");
	result:attachWeaponPart(factoryItem);
	Shared.SetArrowName(result);
end]]

--This one creates a modular arrow item, creates a wooden shaft attachment, and attaches the attachment to the base item
function Server.Recipe.OnMakeArrowShaftWooden(items, result, player, selectedItem)
	local newItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaArrowBlank");
	local factoryItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaAttachmentShaftWood");
	newItem:attachWeaponPart(factoryItem);
	player:getInventory():AddItem(newItem);
	Shared.SetArrowName(newItem);
end

function Server.Recipe.OnConvertArrowShaftWooden(items, result, player, selectedItem)
	local factoryItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaAttachmentShaftWood");
	result:attachWeaponPart(factoryItem);
	Shared.SetArrowName(result);
	Shared.modDataCompatibility(items:get(0));
	for i,v in pairs(items:get(0):getModData()) do
		result:getModData()[i] = v
	end
	if Shared.getModData(result).condition then
		result:setCondition(result:getConditionMax()*Shared.getModData(result).condition);
	end
end

function MBAOarrow_OnCreate(items, result, player, selectedItem)
	for i=0,items:size() - 1 do
        if items:get(i):getType() == "MandelaArrowShaft" then
			Shared.modDataCompatibility(items:get(i));
			if Shared.getModData(items:get(i)).condition ~= nil then
				result:setCondition(result:getConditionMax()*Shared.getModData(items:get(i)).condition);
			end
		end
	end
end

function MBAOtapeArrow_OnCreate(items, result, player, selectedItem)
    local conditionMax = 2 + player:getPerkLevel(Perks.Woodwork);
    conditionMax = ZombRand(conditionMax - 1, conditionMax + 2);
    if conditionMax > result:getConditionMax() then
        conditionMax = result:getConditionMax();
    end
    if conditionMax < 2 then
        conditionMax = 2;
    end
    result:setCondition(conditionMax);
end

function MBAODismantletapedArrow_OnCreate(items, result, player, selectedItem)
    local conditionMax = selectedItem:getCondition();

    if conditionMax > selectedItem:getConditionMax() then
        conditionMax = selectedItem:getConditionMax();
    end
    if conditionMax < 2 then
        conditionMax = 2;
    end
    local shaft = player:getInventory():AddItem("Base.MandelaArrowShaft");
    Shared.getModData(shaft).condition = conditionMax/selectedItem:getConditionMax();
    player:getInventory():AddItem("Base.MandelaFletchings");
end

function Server.Recipe.Dismantlearrow_OnCreate(items, result, player, selectedItem)
    Shared.getModData(result).condition = selectedItem:getCondition()/selectedItem:getConditionMax();
    player:getInventory():AddItem("MandelaBowAndArrow.MandelaArrowHeadIron2");
    player:getInventory():AddItem("MandelaBowAndArrow.MandelaFletchingsDuctTape");
	local factoryItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaAttachmentShaftWood");
	result:attachWeaponPart(factoryItem);
	Shared.SetArrowName(result);
end

function MBAOstringBow_OnCreate(items, result, player, selectedItem)
	for i=0,items:size() - 1 do
        if items:get(i):getType() == "MandelaBowString" or items:get(i):getFullType() == "MandelaBowAndArrow.MandelaBowString2" then
			Shared.modDataCompatibility(items:get(i));
			if Shared.getModData(items:get(i)).condition ~= nil then
				result:setCondition(result:getConditionMax()*Shared.getModData(items:get(i)).condition);
			end
		end
	end
end

function MBAOunstringBow_OnCreate(items, result, player, selectedItem)
    local bowstring = player:getInventory():AddItem("MandelaBowAndArrow.MandelaBowString2");
	Shared.getModData(bowstring).condition = selectedItem:getCondition()/selectedItem:getConditionMax();
	result:setCondition(result:getConditionMax());
end

--When the recipe to create the bow stave is done, which is very quick, it immediately adds the action to carve it into a bow
function MBAObowStave_OnCreate(items, result, player, selectedItem)
    ISTimedActionQueue.add(ISMBAcarveBowStaveAction:new(player, result))
end

if isServer() then
	function Server.OnClientCommand(module, command, playerObj, args)
		if module == "MandelaBowAndArrow" then
			if command == "BowModel" then
				sendServerCommand("MandelaBowAndArrow", "BowModel", args );
			elseif command == "CarveBowStopped" then
				Shared.getModData(args[2]).progress = args[1];
			end
		end
	end
	Events.OnClientCommand.Add(Server.OnClientCommand);
end