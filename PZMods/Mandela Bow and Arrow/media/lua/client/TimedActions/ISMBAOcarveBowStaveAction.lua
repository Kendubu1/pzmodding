--***********************************************************
--**                    ROBERT JOHNSON                     **
--***********************************************************

ISMBAcarveBowStaveAction = ISBaseTimedAction:derive("ISMBAcarveBowStaveAction");
local Client = MandelaBowAndArrow.Client;
local Shared = MandelaBowAndArrow.Shared;

function ISMBAcarveBowStaveAction:isValid()
	return self.character:getInventory():contains(self.item);
end

function ISMBAcarveBowStaveAction:update()
	Shared.getModData(self.item).progress = self.startingProgress + (self:getJobDelta()*(1-self.startingProgress));
	self.item:setJobDelta(Shared.getModData(self.item).progress);
end

function ISMBAcarveBowStaveAction:start()
	self.item:setJobType(self.jobType);
	self.item:setJobDelta(Shared.getModData(self.item).progress);
	self:setOverrideHandModels(nil, self.item);
	self:setActionAnim(CharacterActionAnims.Craft);
	self:setCurrentTime(self.maxTime * (self.item:getJobDelta()))
end

function ISMBAcarveBowStaveAction:stop()
    ISBaseTimedAction.stop(self);
	self.item:setJobDelta(0.0);
	if isClient() then
		sendClientCommand("MandelaBowAndArrow", "CarveBowStopped", {Shared.getModData(self.item).progress, self.item});
	end
end

function ISMBAcarveBowStaveAction:perform()
	local inventory = self.character:getInventory();
    inventory:Remove(self.item);
    --inventory:AddItem("Base.MandelaBowUnstrung");
	inventory:AddItem("MandelaBowAndArrow.MandelaBowWoodLongUnstrung");
	self.character:getXp():AddXP(Perks.Woodwork, 25);
    self.item:setJobDelta(0.0);
	ISBaseTimedAction.perform(self);
end

function ISMBAcarveBowStaveAction:new(character, item)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	if Shared.getModData(item).progress == nil then Shared.getModData(item).progress = 0; end
	o.character = character;
    o.item = item;
	o.stopOnWalk = true;
	o.stopOnRun = true;
	local time = 50000 / (1+((character:getPerkLevel(Perks.Woodwork)-2)/5));
	o.maxTime = time - (Shared.getModData(item).progress*time);
	o.startingProgress = Shared.getModData(item).progress;
    o.caloriesModifier = 4;
	o.jobType = "Making a bow";
    if character:isTimedActionInstant() then
        o.maxTime = 1;
    end
	return o;
end
