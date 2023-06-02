--***********************************************************
--**                    THE INDIE STONE                    **
--***********************************************************

ISMBAUnloadarrowsFromBow = ISUnloadBulletsFromFirearm:derive("ISMBAUnloadarrowsFromBow")

function ISMBAUnloadarrowsFromBow:animEvent(event, parameter)
	if event == 'playReloadSound' then
		if self.gun:getCurrentAmmoCount() <= 0 then
			-- Fix for looping animation events arriving after loading finished.
			-- That's why 'PlaySound' isn't used instead.
			return
		end
		if self.gun:getEjectAmmoSound() then
			self.character:playSound(self.gun:getEjectAmmoSound())
		end
		local count = 1
		if self.gun:isInsertAllBulletsReload() then
			-- Double-barrel shotgun loads/unloads 2 at once.
			count = self.gun:getCurrentAmmoCount()
		end
		while self.gun:getCurrentAmmoCount() > 0 do
			MandelaBowAndArrow.Client.UnloadArrow(self.character, self.gun, 0);
			count = count - 1
			if count == 0 then
				break
			end
		end
		self.unloadFinished = false
	elseif event == 'unloadFinished' then
		if self.gun:getCurrentAmmoCount() <= 0 then
			self.unloadFinished = true;
			MandelaBowAndArrow.Client.SetBowAndArrowModel(self.character, self.gun, 1);
		end
	elseif event == 'changeWeaponSprite' then
		if parameter and parameter ~= '' then
			if parameter ~= 'original' then
				self:setOverrideHandModels(parameter, nil)
			else
				self:setOverrideHandModels(self.gun:getWeaponSprite(), nil)
			end
		end
	end
end

function ISMBAUnloadarrowsFromBow:new(character, gun)
	local o = ISBaseTimedAction.new(self, character)
	o.stopOnAim = false
	o.stopOnWalk = false
	o.stopOnRun = true
	o.maxTime = -1
	o.gun = gun
	o.useProgressBar = false
	return o
end

local original_new = ISUnloadBulletsFromFirearm.new;
function ISUnloadBulletsFromFirearm:new(character, gun)
	if MandelaBowAndArrow.Client.isMandelaBow(gun:getFullType(), 5) then
		return ISMBAUnloadarrowsFromBow:new(character, gun)
	else return original_new(self, character, gun) end
end