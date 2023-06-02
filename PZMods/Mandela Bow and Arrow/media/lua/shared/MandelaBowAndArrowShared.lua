--[[local group = AttachedLocations.getGroup("Human")
for i=0, 360, 10 do
	group:getOrCreateLocation("MBA_forehead_"..tostring(i).."_0"):setAttachmentName("MBA_forehead_"..tostring(i).."_0")
end
]]--
MandelaBowAndArrow = MandelaBowAndArrow or {};
MandelaBowAndArrow.Shared = MandelaBowAndArrow.Shared or {};
MandelaBowAndArrow.Client = MandelaBowAndArrow.Client or {};
MandelaBowAndArrow.Server = MandelaBowAndArrow.Server or {};
local Shared = MandelaBowAndArrow.Shared;
local Client = MandelaBowAndArrow.Client;
Shared.nan = tostring(0/0);
Shared._nan = tostring(-(0/0));

--This mod creates a table inside the thing's modData, and stores its stuff in that.
function Shared.getModData(thing)
	if thing:getModData().MandelaBowAndArrow == nil then thing:getModData().MandelaBowAndArrow = {} end
	return thing:getModData().MandelaBowAndArrow
end

--Older versions of this mod didn't do this, so this function converts old mod type mod data into new type
function Shared.modDataCompatibility(thing)
	local oldModData = thing:getModData();
	local newModData = Shared.getModData(thing);
	if oldModData.MBAOarrowCondition ~= nil then
		newModData.arrowCondition = oldModData.MBAOarrowCondition;
		oldModData.MBAOarrowCondition = nil;
	end
	if oldModData.MBAOarrowFullType ~= nil then
		newModData.arrowFullType = oldModData.MBAOarrowFullType;
		oldModData.MBAOarrowFullType = nil;
	end
	if oldModData.MBAOstaveProgress ~= nil then
		newModData.progress = oldModData.MBAOarrowFullType;
		oldModData.MBAOstaveProgress = nil;
	end
	if oldModData.MBAOcondition ~= nil then
		newModData.condition = oldModData.MBAOcondition;
		oldModData.MBAOcondition = nil;
	end
	if newModData.arrowFullType ~= nil then
		newModData.arrowData = {condition = newModData.condition, fullType = newModData.arrowFullType, modData = {}};
		newModData.arrowFullType = nil;
	end
end

--Arrow shaft names
Shared.ArrowShaftNames = {
	["MandelaBowAndArrow.MandelaAttachmentShaftWood"] = "Arrow Shaft of Wood"
}

--This function sets the name of an arrow
function Shared.SetArrowName(arrow)
	if not arrow:getStock() then
		print("Bow and Arrow mod: SetArrowName trying to set name of arrow with no shaft attachment");
		return;
	end
	local name;
	--local weight = Client.AttachmentWeight[arrow:getStock():getFullType()] or 0;
	if arrow:getRecoilpad() then
		if arrow:getCanon() then
			name = getText("IGUI_MBA_arrow");
		else
			name = getText("IGUI_MBA_arrow_headless");
		end
		if arrow:getRecoilpad():getFullType() == "MandelaBowAndArrow.MandelaAttachmentFletchingsDucttapeFluFlu" then
			name = name .. getText("IGUI_MBA_fluflu");
		end
		--weight = weight + (Client.AttachmentWeight[arrow:getRecoilpad():getFullType()] or 0);
	else
		if arrow:getCanon() then
			name = getText("IGUI_MBA_arrow_unfletched");
		else
			name = Shared.ArrowShaftNames[arrow:getStock():getFullType()];
		end
	end
	if arrow:getCanon() then
		--weight = weight + (Client.AttachmentWeight[arrow:getCanon():getFullType()] or 0);
	end
	--arrow:setActualWeight(weight);
	--arrow:setCustomWeight(true);
	arrow:setName(name);
end

--This gets the game's version number
Shared.versionNumber = tonumber(tostring(getCore():getGameVersion():getMajor()) .. "." .. tostring(getCore():getGameVersion():getMinor()));