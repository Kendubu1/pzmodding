require "TimedActions/ISBaseTimedAction"

MBACraftAction = ISBaseTimedAction:derive("MBACraftAction");

function MBACraftAction:isValid()
	if self.character:isDriving() then return false end
	for i,v in pairs(self.arrows) do
		if not self.container:contains(v) then return false end
	end
	for i,v in pairs(self.arrowParts) do
		if not self.container:contains(v) then return false end
	end
	return true
end

function MBACraftAction:update()
	self.item:setJobDelta(self:getJobDelta());
	--    if self.recipe:getSound() and (not self.craftSound or not self.craftSound:isPlaying()) then
	--        self.craftSound = getSoundManager():PlayWorldSoundWav(self.recipe:getSound(), self.character:getCurrentSquare(), 0, 2, 1, true);
	--    end
	self.character:setMetabolicTarget(Metabolics.UsingTools);
end

function MBACraftAction:start()
	if self.recipe.workSound then
		self.craftSound = self.character:getEmitter():playSound(self.recipe.workSound);
	end
	self.item:setJobType(self.recipe.name);
	self.item:setJobDelta(0.0);
	if self.recipe.prop1 or self.recipe.prop1 then
		self:setOverrideHandModels(self[prop1], self[prop2])
	end
	if self.recipe.animNode then
		self:setActionAnim(self.recipe.animNode);
	else
		self:setActionAnim(CharacterActionAnims.Craft);
	end

	--	self.character:reportEvent("EventCrafting");
end

function MBACraftAction:stop()
	if self.craftSound and self.character:getEmitter():isPlaying(self.craftSound) then
		self.character:getEmitter():stopSound(self.craftSound);
	end
	self.item:setJobDelta(0.0);
	ISBaseTimedAction.stop(self);
end

function MBACraftAction:perform()
	if self.craftSound and self.character:getEmitter():isPlaying(self.craftSound) then
		self.character:getEmitter():stopSound(self.craftSound);
	end
	self.container:setDrawDirty(true);
	self.item:setJobDelta(0.0);
	
	self.recipe.done(self);

	ISInventoryPage.dirtyUI()

	if self.onCompleteFunc then
		local args = self.onCompleteArgs
		self.onCompleteFunc(args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8])
	end

	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self);
end

function MBACraftAction:setOnComplete(func, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
	self.onCompleteFunc = func
	self.onCompleteArgs = { arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8 }
end

function MBACraftAction:new(character, item, time, recipe, container)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character;
	o.item = item;
	o.recipe = recipe;
	o.container = container;
	o.stopOnWalk = recipe.stopOnWalk;
	o.stopOnRun = recipe.stopOnRun;
	o.maxTime = time;
	o.arrows = {};
	o.arrowParts = {};
	if character:isTimedActionInstant() then
		o.maxTime = 1;
	end
	o.jobType = getText(recipe.name);
	o.forceProgressBar = true;
	return o;
end
