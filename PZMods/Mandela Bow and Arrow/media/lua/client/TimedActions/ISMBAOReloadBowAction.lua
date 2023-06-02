--***********************************************************
--**                    ROBERT JOHNSON                     **
--***********************************************************

ISMBAReloadBowAction = ISBaseTimedAction:derive("ISMBAReloadBowAction");

function ISMBAReloadBowAction:isValid()
	return self.character:getPrimaryHandItem() == self.gun
end

function ISMBAReloadBowAction:update()
end

ISMBAReloadBowAction.canRack = function(weapon)
	if not weapon:getMagazineType() and not weapon:getAmmoType() then
		return false
	end
	if weapon:isJammed() then
		return true
	end
	if weapon:haveChamber() and weapon:isRoundChambered() then
		return true
	end
	if weapon:haveChamber() and weapon:isSpentRoundChambered() then
		return true
	end
	if weapon:haveChamber() and not weapon:isRoundChambered() and weapon:getMagazineType() and weapon:getCurrentAmmoCount() > 0 then
		return true
	end
	if not weapon:haveChamber() and weapon:getCurrentAmmoCount() > 0 then
		return true
	end
	if not weapon:getMagazineType() and weapon:getCurrentAmmoCount() >= weapon:getAmmoPerShoot() then
		return true;
	end
	return false;
end

function ISMBAReloadBowAction:start()
	-- Setup IsPerformingAction & the current anim we want (check in AnimSets LoadHandgun.xml for example)
	self:setActionAnim(CharacterActionAnims.Reload);
	self.character:setVariable("WeaponReloadType", self.gun:getWeaponReloadType());
	self.character:setVariable("isLoading", true);
	self:setOverrideHandModels(self.gun, nil);
	self.ammoCountStart = self.gun:getCurrentAmmoCount()
	self.gun:setJobType(getText("IGUI_JobType_LoadBulletsIntoFirearm"))
	self.gun:setJobDelta(0.0)

	self:initVars();

	-- no arrows were found
	if (not self.hasArrow) or self.gun:getCurrentAmmoCount() > 0 then
		self:forceStop();
	end
end

-- This is used by other timed actions.
function ISMBAReloadBowAction:setReloadSpeed(character, rack)
	local baseDrawSpeed = 0.35;
	local baseNockSpeed = 0.5;
	local baseReloadSpeed = 1;
	if rack then
		-- reloading skill has less impact on racking, panic does nothing
		baseReloadSpeed = baseReloadSpeed + (character:getPerkLevel(Perks.Reloading) * 0.03);
	else
		local bullet = MandelaBowAndArrow.Shared.getModData(self.gun).bullet;
		if bullet then
			local container = bullet:getContainer();
			local quiverType = MandelaBowAndArrow.Shared.QuiverTypes[bullet:getContainer():getType()];
			if quiverType then
				baseDrawSpeed = quiverType.ChangeReloadSpeed(character, baseDrawSpeed);
			end
		end
		local panic = character:getStats():getPanic() / 400;
		local drunkenness = character:getStats():getDrunkenness() / 100;
		local fatigue = character:getStats():getFatigue();
		fatigue = (fatigue - 0.75)*2; if fatigue < 0 then fatigue = 0; end
		if MandelaBowAndArrow.Client.getArcherySkill(character) == 0 then
			baseReloadSpeed = baseReloadSpeed * 0.4;
		else
			baseReloadSpeed = baseReloadSpeed * 0.4 / (0.85^MandelaBowAndArrow.Client.getArcherySkill(character));
		end
		baseReloadSpeed = baseReloadSpeed / ((1+panic)*(1+drunkenness)*(1+fatigue));
		--baseReloadSpeed = baseReloadSpeed - (character:getMoodles():getMoodleLevel(MoodleType.Panic) * 0.05);
	end
	character:setVariable("ReloadSpeed", (baseDrawSpeed + baseNockSpeed) * baseReloadSpeed * GameTime.getAnimSpeedFix());
end

-- Add some vars we gonna use, either magazine or the bullets
-- also decide the reload speed
function ISMBAReloadBowAction:initVars()
	--ISMBAReloadBowAction.setReloadSpeed(self.character, false);
	self:setReloadSpeed(self.character, false);
	local containers = {self.character:getInventory()};
	if self.arrowFullType ~= nil then
		self.hasArrow = true;
		local arrowItem = self.character:getInventory():getItemFromType(self.arrowFullType);
		local priority = MandelaBowAndArrow.Client.AmmoTypes[self.arrowFullType].priority;
		if "MandelaBowAndArrow.MandelaArrowBlank" == self.arrowFullType then
			priority = 3
		end
		self.arrows = {priority, self.arrowFullType, {arrowItem}};
	else
		self.arrows = {};
		self.hasArrow = false;
		local blankTable = {}
		MandelaBowAndArrow.Client.CheckForQuivers(self.character, containers);
		for containerIndex, specificContainer in pairs(containers) do
			for itemFullType,v in pairs(MandelaBowAndArrow.Client.AmmoTypes) do
				local arrowsArray = specificContainer:getItemsFromFullType(itemFullType);
				if arrowsArray ~= nil then
					if not arrowsArray:isEmpty() then
						local addedOne = false
						for i2 = 1, arrowsArray:size() do
							local arrow = arrowsArray:get(i2-1);
							if arrow:getCondition() > 0 then
								if itemFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
									local priority = 0.5;
									if arrow:getRecoilpad() then
										priority = priority + 1;
									end
									if arrow:getCanon() then
										priority = priority + 1.5;
									end
									local tableName = "MandelaArrowBlank" .. tostring(priority);
									if blankTable[tableName] == nil then 
										self.arrows[#self.arrows+1] = {priority, itemFullType, {}};
										blankTable[tableName] = self.arrows[#self.arrows];
									end
									blankTable[tableName][3][#blankTable[tableName][3]+1] = arrow;
									self.hasArrow = true;
								else
									if not addedOne then 
										self.arrows[#self.arrows+1] = {MandelaBowAndArrow.Client.AmmoTypes[itemFullType].priority, itemFullType, {}};
										addedOne = true;
									end
									self.arrows[#self.arrows][3][#self.arrows[#self.arrows][3]+1] = arrow;
									self.hasArrow = true;
									break
								end
							end
						end
					end
				end
			end
		end
	end
	local addingArrow = nil;
	local highestPriority = 0;
	for i=1, #self.arrows do
		if self.arrows[i][1] > highestPriority then
			addingArrow = self.arrows[i][3][1];
			highestPriority = self.arrows[i][1];
		end
	end
	MandelaBowAndArrow.Shared.getModData(self.gun).addingArrow = addingArrow;
	if addingArrow ~= nil then
		MandelaBowAndArrow.Shared.getModData(self.gun).bullet = addingArrow;
	end
end

function ISMBAReloadBowAction:stop()
	self.gun:setJobDelta(0.0);
	-- this should already be cleared from event, but who knows right?
	self.character:clearVariable("isLoading");
	self.character:clearVariable("WeaponReloadType");
	MandelaBowAndArrow.Shared.getModData(self.gun).bullet = nil;
	ISBaseTimedAction.stop(self);
end

function ISMBAReloadBowAction:perform()
	self.gun:setJobDelta(0.0);
	self.character:clearVariable("isLoading");
	self.character:clearVariable("WeaponReloadType");
	MandelaBowAndArrow.Shared.getModData(self.gun).bullet = nil;
	ISBaseTimedAction.perform(self);
end

-- Our AnimSet trigger various event, we hook them here. Check LoadHandgun.xml for example.
function ISMBAReloadBowAction:animEvent(event, parameter)
	-- Loading clip is done, we're moving to racking if needed
	if event == 'loadFinished' then
		self:loadAmmo();
	end
	if event == 'playReloadSound' then
		if parameter == 'load' then
			if self.gun:getInsertAmmoSound() and self.gun:getCurrentAmmoCount() < self.gun:getMaxAmmo() then
				self.character:playSound(self.gun:getInsertAmmoSound());
			end
		end
	end
	if event == 'changeWeaponSprite' then
		if parameter and parameter ~= '' then
			if parameter ~= 'original' then
				self:setOverrideHandModels(parameter, nil)
			else
				self:setOverrideHandModels(self.gun:getWeaponSprite(), nil)
			end
		end
	end
end

function ISMBAReloadBowAction:loadAmmo()
	-- we insert a new clip only if we're in the motion of loading
	if self.arrows and self.hasArrow then -- insert bullets one by one
		local addingArrow = MandelaBowAndArrow.Shared.getModData(self.gun).bullet;
		if addingArrow ~= nil and self.gun:getCurrentAmmoCount() < self.gun:getMaxAmmo() then
			self.character:getSquare():playSound("ChatDrawCard");
			MandelaBowAndArrow.Shared.modDataCompatibility(self.gun);
			local arrowData = {};
			arrowData.condition = addingArrow:getCondition();
			arrowData.fullType = addingArrow:getFullType();
			local modDataCopy = {};
			for i,v in pairs(addingArrow:getModData()) do
				table.insert(modDataCopy, {i, v});
			end
			if modDataCopy.MandelaBowAndArrow and modDataCopy.MandelaBowAndArrow.note then
				modDataCopy.MandelaBowAndArrow.note = nil;
			end
			arrowData.modData = modDataCopy;
			MandelaBowAndArrow.Shared.getModData(self.gun).arrowData = arrowData;
			--self.character:getInventory():Remove(addingArrow);
			addingArrow:getContainer():Remove(addingArrow);
			self.gun:setCurrentAmmoCount(self.gun:getCurrentAmmoCount() + 1);
			if addingArrow:getFullType() == "MandelaBowAndArrow.MandelaArrowBlank" then
				if addingArrow:getStock() then
					arrowData.stockFullType = addingArrow:getStock():getFullType();
					local factoryItem = InventoryItemFactory.CreateItem(addingArrow:getStock():getFullType());
					self.gun:attachWeaponPart(factoryItem);
					if addingArrow:getCanon() then
						arrowData.canonFullType = addingArrow:getCanon():getFullType();
						factoryItem = InventoryItemFactory.CreateItem(addingArrow:getCanon():getFullType());
						self.gun:attachWeaponPart(factoryItem);
					end
					if addingArrow:getRecoilpad() then
						arrowData.recoilpadFullType = addingArrow:getRecoilpad():getFullType();
						factoryItem = InventoryItemFactory.CreateItem(addingArrow:getRecoilpad():getFullType());
						self.gun:attachWeaponPart(factoryItem);
					end
				else
					print("Bow and Arrow mod: arrow has no shaft attachment");
					arrowData.fullType = "Base.MandelaArrowWoodDucttapeIron";
				end
			else
				local factoryItem = InventoryItemFactory.CreateItem(addingArrow:getFullType() .. "Attachment");
				self.gun:attachWeaponPart(factoryItem);
			end
			self.character:resetEquippedHandsModels();
			MandelaBowAndArrow.Shared.getModData(self.character).hasShot = false;
		end
		self.character:clearVariable("isLoading");
		self:forceStop();
	end
end

-- if reload is true we remove our current clip if we have one & equip a new one
-- if false we simply just remove the clip or ammos we have in our gun
function ISMBAReloadBowAction:new(character, gun, arrowFullType)
	local o = ISBaseTimedAction.new(self, character)
	o.stopOnAim = false;
	o.stopOnWalk = false;
	o.stopOnRun = true;
	o.gun = gun;
	o.maxTime = -1; -- we don't care about time, the anim is controlling the speed/time
	o.useProgressBar = false;
	o.arrowFullType = arrowFullType;
	return o;
end

-- Called when pressing reload button when not already reloading, only called when you have an equipped weapon to reload (with available bullets or clip)
local original_OnPressReloadButton = ISReloadWeaponAction.OnPressReloadButton;
Events.OnPressReloadButton.Remove(ISReloadWeaponAction.OnPressReloadButton);
ISReloadWeaponAction.OnPressReloadButton = function(player, gun)
	if MandelaBowAndArrow.Client.isMandelaBow(gun:getFullType()) then
		if ISReloadWeaponAction.disableReloading then
			return;
		end
		-- If you press reloading while loading bullets, we stop and rack
		if player:getVariableBoolean("isLoading") then
			ISTimedActionQueue.clear(player);
			ISTimedActionQueue.add(ISRackFirearm:new(player, gun));
		else
			ISTimedActionQueue.add(ISMBAReloadBowAction:new(player, gun));
			-- See ISFirearmRadialMenu.onKeyReleased()
		end
	else
		original_OnPressReloadButton(player, gun);
	end
end
Events.OnPressReloadButton.Add(ISReloadWeaponAction.OnPressReloadButton);

-- Called when pressing rack (if you rack while having a clip/bullets, we simply remove it and don't reload a new one)
local original_OnPressRackButton = ISReloadWeaponAction.OnPressRackButton
Events.OnPressRackButton.Remove(ISReloadWeaponAction.OnPressRackButton);
ISReloadWeaponAction.OnPressRackButton = function(player, gun)
	if MandelaBowAndArrow.Client.isMandelaBow(gun:getFullType()) then
		if ISReloadWeaponAction.disableReloading then
			return;
		end
		if not ISMBAReloadBowAction.canRack(gun) then
			return;
		end
		-- if you press rack while loading bullets, we stop and rack
		if player:getVariableBoolean("isLoading") and not gun:isRoundChambered() then
			ISTimedActionQueue.clear(player);
		end
		ISTimedActionQueue.add(ISRackFirearm:new(player, gun));
	else
		original_OnPressRackButton(player, gun);
	end
end
Events.OnPressRackButton.Add(ISReloadWeaponAction.OnPressRackButton);

ISMBAReloadBowAction.canShoot = function(weapon)
	if getDebug() and getDebugOptions():getBoolean("Cheat.Player.UnlimitedAmmo") then
		return true;
	end
	if weapon:isJammed() then
		return false;
	end
	if weapon:haveChamber() and not weapon:isRoundChambered() then
		return false;
	end
	if not weapon:haveChamber() and weapon:getCurrentAmmoCount() <= 0 then
		return false;
	end
	return true;
end

local original_new = ISReloadWeaponAction.new;
function ISReloadWeaponAction:new(character, gun, rack, magazine)
	if MandelaBowAndArrow.Client.isMandelaBow(gun:getFullType()) then
		return ISMBAReloadBowAction:new(character, gun, rack, magazine)
	else return original_new(self, character, gun, rack, magazine) end
end