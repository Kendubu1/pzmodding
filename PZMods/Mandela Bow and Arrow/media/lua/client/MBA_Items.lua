
--*****************************************************************
--**                    Are ya winning, son?                     **
--*****************************************************************

local Shared = MandelaBowAndArrow.Shared;
local Client = MandelaBowAndArrow.Client;

Client.Bows = Client.Bows or {};

Client.Bows["Base.MandelaBow"] = {
	speed = 0.25,
	aimingAngle = 30,
	aimingDistance = 17,
	weaponOffset = 0.9,
	deviationMultiplier = 1.5,
	--gravity = 0.003, --does nothing apparently
	model = "MandelaBowAndArrow.MandelaBow",
	soundVolume = 1,
	soundRadius = 4};

Client.Bows["MandelaBowAndArrow.CompoundBowScorpion"] = {
	speed = 0.3,
	aimingAngle = 30,
	aimingDistance = 17,
	weaponOffset = 0.9,
	deviationMultiplier = 1.3,
	model = "MandelaBowAndArrow.CompoundBowScorpion",
	soundVolume = 1,
	soundRadius = 4};

Client.Bows["MandelaBowAndArrow.MandelaBowWoodLong"] = {
	speed = 0.25,
	aimingAngle = 30,
	aimingDistance = 17,
	weaponOffset = 0.9,
	deviationMultiplier = 1.5,
	model = "MandelaBowAndArrow.MandelaBow",
	soundVolume = 1,
	soundRadius = 4};

--Data for older type arrows like before modular arrows were added. You can still add non-modular arrows.
Client.AmmoTypes = Client.AmmoTypes or {};
Client.AmmoTypes["Base.MandelaArrowWoodDucttapeIronTaped"] = {priority = 1, quiver = true, model = "MandelaBowAndArrow.MandelaArrowWoodDucttapeIronTaped"};
Client.AmmoTypes["Base.MandelaArrowWoodDucttapeIron"] = {priority = 3, quiver = true, model = "MandelaBowAndArrow.MandelaArrowWoodDucttapeIron"};
Client.AmmoTypes["MandelaBowAndArrow.MandelaArrowBlank"] = {quiver = true};

Client.NoMandelaCustomTooltip = Client.NoMandelaCustomTooltip or {};

function Client.isMandelaBow(itemFullType, number)
	if Client.Bows[itemFullType] ~= nil
	then return true;
	else return false; end
end

Client.logo = getTexture("media/ui/Traits/trait_MBAOarcher.png");
Client.arrowBlankTexture = getTexture("media/textures/Item_MBA_ModularArrow_Blank.png");
Client.arrowBlankTextureName = Client.arrowBlankTexture:getName();

Client.Sounds = {
	HitTile = "ChopTree",
	HitHead = "ChopTree",
	HitBody = "ChopTree"
}

------------------------------------------------------------------
Client.QuiverTypes = Client.QuiverTypes or {};
if not Client.QuiverTypes["QuiverB"] then
	Client.QuiverTypes["QuiverB"] = {
		Type = "InventoryContainer",
		CheckIfHas = function (character)
			for i=0, character:getWornItems():size()-1 do
				local item = character:getWornItems():getItemByIndex(i);
				if item:getType() == "QuiverB" then return item:getInventory() end
			end
			return nil
		end,
		ChangeReloadSpeed = function (character, baseLoadSpeed)
			return baseLoadSpeed + 0.3;
		end
	};
end

function Client.CheckForQuivers(character, quiverTable)
	for i,v in pairs (Client.QuiverTypes) do
		if v.CheckIfHas(character) then
			table.insert(quiverTable, 1, v.CheckIfHas(character))
		end
	end
end
-- For adding compatibility with a quiver from a mod that adds a quiver.
------------------------------------------------------------------

--For example, MandelaBowAndArrow.MandelaArrowHeadIron2 is an item seen in the inventory, whereas MandelaBowAndArrow.MandelaAttachmentHeadIron a "WeaponPart" sort of item that adds a model to the arrow when attached.
Client.AttachmentConversion = {
	["Base.MandelaArrowHeadIron"] = "MandelaBowAndArrow.MandelaAttachmentHeadIron",
	["MandelaBowAndArrow.MandelaArrowHeadIron2"] = "MandelaBowAndArrow.MandelaAttachmentHeadIron",
	["MandelaBowAndArrow.MandelaAttachmentHeadIron"] = "MandelaBowAndArrow.MandelaArrowHeadIron2",
	
	["MandelaBowAndArrow.MandelaArrowHeadFlint"] = "MandelaBowAndArrow.MandelaAttachmentHeadFlint",
	["MandelaBowAndArrow.MandelaAttachmentHeadFlint"] = "MandelaBowAndArrow.MandelaArrowHeadFlint",
	
	["Base.MandelaFletchings"] = "MandelaBowAndArrow.MandelaAttachmentFletchingsDucttape",
	["MandelaBowAndArrow.MandelaFletchingsDuctTape"] = "MandelaBowAndArrow.MandelaAttachmentFletchingsDucttape",
	["MandelaBowAndArrow.MandelaAttachmentFletchingsDucttape"] = "MandelaBowAndArrow.MandelaFletchingsDuctTape",
	
	["MandelaBowAndArrow.MandelaFletchingsDuctTapeFluFlu"] = "MandelaBowAndArrow.MandelaAttachmentFletchingsDucttapeFluFlu",
	["MandelaBowAndArrow.MandelaAttachmentFletchingsDucttapeFluFlu"] = "MandelaBowAndArrow.MandelaFletchingsDuctTapeFluFlu"
}
--[[
Client.AttachmentIcons = {
	["MandelaBowAndArrow.MandelaAttachmentShaftWood"] = getTexture("media/textures/Item_MBA_ModularArrow_ShaftWood.png"),
	["MandelaBowAndArrow.MandelaAttachmentHeadIron"] = getTexture("media/textures/Item_MBA_ModularArrow_HeadIron1.png"),
	["MandelaBowAndArrow.MandelaAttachmentHeadIronTaped"] = getTexture("media/textures/Item_MBA_ModularArrow_HeadIronTaped.png"),
	["MandelaBowAndArrow.MandelaAttachmentFletchingsDucttape"] = getTexture("media/textures/Item_MBA_ModularArrow_FletchingsDuctTape.png"),
}]]--

Client.ArrowPartData = {
	["Base.MandelaArrowHeadIron"] = {sort = "Head"},
	["MandelaBowAndArrow.MandelaArrowHeadIron2"] = {sort = "Head"},
	["MandelaBowAndArrow.MandelaArrowHeadFlint"] = {sort = "Head"},
	["Base.MandelaFletchings"] = {sort = "Fletchings"},
	["MandelaBowAndArrow.MandelaFletchingsDuctTape"] = {sort = "Fletchings"},
	["MandelaBowAndArrow.MandelaFletchingsDuctTapeFluFlu"] = {sort = "Fletchings", fluflu = true}
}

--Arrow parts should increase the arrow's weight by amount specific to the parts.
Client.AttachmentWeight = {
	["MandelaBowAndArrow.MandelaAttachmentShaftWood"] = 0.03,
	["MandelaBowAndArrow.MandelaAttachmentHeadIron"] = 0.07,
	["MandelaBowAndArrow.MandelaAttachmentHeadIronTaped"] = 0.07,
	["MandelaBowAndArrow.MandelaAttachmentHeadFlint"] = 0.07,
	["MandelaBowAndArrow.MandelaAttachmentFletchingsDucttape"] = 0.01,
	["MandelaBowAndArrow.MandelaAttachmentFletchingsDucttapeFluFlu"] = 0.02
}

--This is for a custom recipe-like system.
Client.Recipes = {}

Client.Recipes.AddArrowHead = {
	name = getText("IGUI_MBA_recipe_AddArrowHead"),
	workSound = nil,
	animNode = nil,
	stopOnWalk = true,
	stopOnRun = true,
	prop1 = "arrow",
	skill = {Woodwork = 2},
	time = 30,
	done = function(self)
		local arrowHead = table.remove(self.arrowParts, 1);
		local arrow = table.remove(self.arrows, 1);
		local factoryItem = InventoryItemFactory.CreateItem(Client.AttachmentConversion[arrowHead:getFullType()]);
		arrow:attachWeaponPart(factoryItem);
		self.container:Remove(arrowHead);
		Shared.SetArrowName(arrow);
		self.character:resetEquippedHandsModels();
	end
}

Client.Recipes.AddFletchings = {
	name = getText("IGUI_MBA_recipe_AddFletchings"),
	workSound = nil,
	animNode = nil,
	stopOnWalk = true,
	stopOnRun = true,
	prop1 = "arrow",
	time = 30,
	done = function(self)
		local fletchings = table.remove(self.arrowParts, 1);
		local arrow = table.remove(self.arrows, 1);
		local factoryItem = InventoryItemFactory.CreateItem(Client.AttachmentConversion[fletchings:getFullType()]);
		arrow:attachWeaponPart(factoryItem);
		self.container:Remove(fletchings);
		Shared.SetArrowName(arrow);
		self.character:resetEquippedHandsModels();
	end
}

Client.Recipes.RemoveArrowHead = {
	name = getText("IGUI_MBA_recipe_RemoveArrowHead"),
	workSound = nil,
	animNode = nil,
	stopOnWalk = true,
	stopOnRun = true,
	prop1 = "arrow",
	time = 30,
	done = function(self)
		local arrow = table.remove(self.arrows, 1);
		local arrowHead = arrow:getCanon()
		arrow:detachWeaponPart(arrowHead);
		local factoryItem = InventoryItemFactory.CreateItem(Client.AttachmentConversion[arrowHead:getFullType()]);
		self.character:getInventory():AddItem(factoryItem);
		Shared.SetArrowName(arrow);
		self.character:resetEquippedHandsModels();
	end
}

Client.Recipes.RemoveFletchings = {
	name = getText("IGUI_MBA_recipe_RemoveFletchings"),
	workSound = nil,
	animNode = nil,
	stopOnWalk = true,
	stopOnRun = true,
	prop1 = "arrow",
	time = 30,
	done = function(self)
		local arrow = table.remove(self.arrows, 1);
		local arrowFletching = arrow:getRecoilpad()
		arrow:detachWeaponPart(arrowFletching);
		local factoryItem = InventoryItemFactory.CreateItem(Client.AttachmentConversion[arrowFletching:getFullType()]);
		self.character:getInventory():AddItem(factoryItem);
		Shared.SetArrowName(arrow);
		self.character:resetEquippedHandsModels();
	end
}

Client.Recipes.SnapIntoTwigs = {
	name = getText("IGUI_MBA_snap_into_twigs"),
	workSound = nil,
	animNode = nil,
	stopOnWalk = false,
	stopOnRun = true,
	prop1 = "arrow",
	time = 30,
	done = function(self)
		local arrow = table.remove(self.arrows, 1);
		local arrowHead = arrow:getCanon();
		if arrowHead then
			arrow:detachWeaponPart(arrowHead);
			local factoryItem = InventoryItemFactory.CreateItem(Client.AttachmentConversion[arrowHead:getFullType()]);
			self.character:getInventory():AddItem(factoryItem);
		end
		
		local arrowFletching = arrow:getRecoilpad();
		if arrowFletching then
			arrow:detachWeaponPart(arrowFletching);
			local factoryItem = InventoryItemFactory.CreateItem(Client.AttachmentConversion[arrowFletching:getFullType()]);
			self.character:getInventory():AddItem(factoryItem);
		end
		
		self.character:getInventory():Remove(arrow);
		self.character:resetEquippedHandsModels();
		local factoryItem = InventoryItemFactory.CreateItem("Base.Twigs");
		self.character:getInventory():AddItem(factoryItem);
	end
}