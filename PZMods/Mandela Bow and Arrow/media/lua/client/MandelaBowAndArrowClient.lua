
--***************************************************
--**                    Ya boi                     **
--***************************************************

local Shared = MandelaBowAndArrow.Shared;
local Client = MandelaBowAndArrow.Client;

Client.alternativeDrawing = false;

local math = math;

function Client.getArcherySkill(character)
	if Shared.versionNumber ~= nil and Shared.versionNumber < 41.51 and Shared.versionNumber > 40 then
		return character:getModData().skills["Archery"].level
	else
		return character:getPerkLevel(Perks.Archery)
	end
end

function Client.addArcheryXP(character, XP)
	if Shared.versionNumber ~= nil and Shared.versionNumber < 41.51 and Shared.versionNumber > 40  then
		extraskills.addXP(character, "Archery", XP);
	else
		character:getXp():AddXP(Perks.Archery, XP);
	end
end

local function StrReplace(thisString, findThis, replaceWithThis)
	return string.gsub(thisString, "("..findThis..")", replaceWithThis);
end

local function IsIn(big,small)
	local temp = StrReplace(big,small,"");
	if(temp == big) then
	return false
	else 
	return true;
	end
end

local function Deepprint(_table, recursions)
	for i,v in pairs(_table) do
		print(recursions, i, v);
		if type(v)=="table" then
			Deepprint(v, recursions + 1)
		end
	end
end

--When an arrow hits a zombie, an arrow should be added to its inventory. This can be done by attaching the zombie to its face or tummy, or by copying the arrow's modData to the zombie so a copy of it can be created later.
function Client.arrowInZombie(target, ArrowItem, modData, i, headShot)
	local usingModData = false;
	local targetModData = Shared.getModData(target);
	if headShot then
		if targetModData.headAttached then
			usingModData = true;
		else
			if ArrowItem:getType() == "MandelaArrowWoodDucttapeIronTaped" then
				Shared.getModData(ArrowItem).note = "Though this arrow hit the head, it went too shallow. It was stopped by the shaft";
			end
			--[[
			local ArrowXSpeed = modData.MandelaBowAndArrowArrowXSpeed[i];
			local ArrowYSpeed = modData.MandelaBowAndArrowArrowYSpeed[i];
			local ArrowZSpeed = modData.MandelaBowAndArrowArrowZSpeed[i];
			
			local yaw = math.atan2(ArrowXSpeed, ArrowYSpeed);
			print("math.deg(yaw): "..tostring(math.deg(yaw)));
			yaw = math.deg(yaw) - 90;
			yaw = yaw / 10;
			yaw = math.floor(yaw+0.5)*10;
			if yaw < 0 then yaw = yaw + 360; end
			ArrowItem:setWeaponSprite("MandelaBowAndArrow." .. ArrowItem:getType() .. "Middle");
			print("math.deg(yaw): "..tostring(yaw));
			
			local attachmentName = "MBA_forehead_"..tostring(yaw).."_0";
			print("attachmentName: "..tostring(attachmentName));]]--
			-- needs the direction the zombie is facing, to do later if ever
			
			local attachmentName = "JawStab";
			target:setAttachedItem(attachmentName, ArrowItem);
			targetModData.headAttached = true;
		end
	else
		if targetModData.bodyAttached then
			usingModData = true;
		else
			target:setAttachedItem("Knife Stomach", ArrowItem);
			targetModData.bodyAttached = true;
		end
	end
	
	local arrowFullType = ArrowItem:getFullType();
	local number = ZombRand(100);
	local condition = ArrowItem:getCondition();
	if number <= (100/(ArrowItem:getConditionLowerChance()*10)) then condition = condition - 1; end
	if number <= (100/(ArrowItem:getConditionLowerChance()*30)) then condition = 0; end
	
	if usingModData then
		local modDataCopy = {};
		for i,v in pairs(ArrowItem:getModData()) do
			table.insert(modDataCopy, {i, v});
		end
		
		if headShot and ArrowItem:getType() == "MandelaArrowWoodDucttapeIronTaped" then
			modDataCopy.note = "Though this arrow hit the head, it went too shallow. It was stopped by the shaft";
		end
		
		local arrowData = {fullType = arrowFullType, condition = condition, modData = modDataCopy};
		if targetModData.arrowTable == nil then targetModData.arrowTable = {} end
		table.insert(targetModData.arrowTable, arrowData);
	else
		ArrowItem:setCondition(condition);
	end
	
	if arrowFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
		Shared.SetArrowName(ArrowItem);
	end
	
	target:transmitModData();
	
	modData.MandelaBowAndArrowInZombieAsAttachment[i] = (not usingModData);
	modData.MandelaBowAndArrowQueuedForRemoval[i] = true;
end

--Based on a drivecars function. It checks for collision with a zombie, a cylinder for its head and a bigger cylinder for the body below the head.
function Client.ArrowHitZombie(X,Y,Z,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,canDamage)
	if not modData.MandelaBowAndArrowQueuedForRemoval[i] then
		local Square = getWorld():getCell():getOrCreateGridSquare(X,Y,Z);
		if Square ~= nil then
			local movingObjects = Square:getMovingObjects();
			local slayZombie = nil;
			if(movingObjects ~= nil) then
				for ii=0, movingObjects:size()-1 do
					if not modData.MandelaBowAndArrowQueuedForRemoval[i] then
						if string.find(tostring(movingObjects:get(ii)),"IsoFallingClothing") == nil then
						--if movingObjects:get(ii):getObjectName() ~= "FallingClothing" then
							if( movingObjects:get(ii):isZombie() ) then
								local target = movingObjects:get(ii);
								local targetX = target:getX();
								local targetY = target:getY();
								local targetZ = target:getZ();
								if (((targetX-ArrowX)^2)+((targetY-ArrowY)^2)) < 0.3^2 then
									if (ArrowZ - math.floor(ArrowZ)) > 0.50 then
										if (((targetX-ArrowX)^2)+((targetY-ArrowY)^2)) < 0.2^2 then
											local damage = ArrowItem:getMaxDamage() * (10 + ZombRand(20));
											local to_brain = canDamage;
											if ArrowItem:getType() == ("MandelaArrowWoodDucttapeIronTaped") then
												to_brain = false
											end
											if ArrowItem:getFullType() == ("MandelaBowAndArrow.MandelaArrowBlank") then
												if ArrowItem:getCanon() then
													if ArrowItem:getCanon():getFullType() == "MandelaBowAndArrow.MandelaAttachmentHeadIronTaped" then
														to_brain = false
													end
												else
													--to_brain = false
													damage = ArrowItem:getMaxDamage() * (3 + ZombRand(8));
												end
											end
											local number = ZombRand(100);
											if number > ArrowItem:getCriticalChance() and number ~= 0 then damage = damage * 5 end
											Client.arrowInZombie(target,ArrowItem,modData,i,true);
													--[[target:Kill(player);
													target:DoZombieInventory();
													triggerEvent("OnZombieDead", target);
													player:setZombieKills(player:getZombieKills()+1);]]--
											target:getSquare():playSound(Client.Sounds.HitHead);
											addSound(player, targetX, targetY, target:getZ(), 5, 1);
											if not to_brain then
												Client.hitConsequencesCMD(target, ArrowItem, player, true, damage, false);
											else
												Client.hitConsequencesCMD(target, ArrowItem, player, false, damage, false);
											end
											modData.MandelaBowAndArrowQueuedForRemoval[i] = true;
										end
									else
										Client.arrowInZombie(target,ArrowItem,modData,i,false);
										target:getSquare():playSound(Client.Sounds.HitBody);
										Client.hitConsequencesCMD(target, ArrowItem, player, true, 0, true);
										modData.MandelaBowAndArrowQueuedForRemoval[i] = true;
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

--Things need to be different depending on whether or not it's multiplayer.
function Client.hitConsequencesCMD(target, weapon, player, ignoreDamage, damage, ignoreStagger)
	if isClient() then
		if not ignoreDamage then
			target:Kill(player);
			target:DoZombieInventory();
			triggerEvent("OnZombieDead", target);
			player:setZombieKills(player:getZombieKills()+1);
		end
	else
		if ignoreStagger == nil then
			target:hitConsequences(weapon, player, ignoreDamage, damage);
		else
			target:hitConsequences(weapon, player, ignoreDamage, damage, ignoreStagger);
		end
	end
end

--This could have been done with neater variable names.
function Client.removeShotArrow(player,i,Square,ArrowX,ArrowY,ArrowZ)
	local modData = Shared.getModData(player);
	if modData.MandelaBowAndArrowQueuedForRemoval[i] then
		local ArrowItem = modData.MandelaBowAndArrowArrowItem[i];
		if ((ArrowItem ~= nil)  ) then
			if Square == nil then print("Bow and Arrow mod Error: Square is nil (1)"); end
			if ((not modData.MandelaBowAndArrowLeavingArrow[i]) and (not modData.MandelaBowAndArrowInZombieAsAttachment[i]) ) then
				ArrowItem:getWorldItem():getSquare():transmitRemoveItemFromSquare(ArrowItem:getWorldItem());
				ArrowItem:getWorldItem():removeFromSquare();
			else
				if ArrowItem:getWorldItem() == nil and Square ~= nil then Square:AddWorldInventoryItem(ArrowItem,0.5,0.5,0); print("Arrow hit invisible barrier?") end
				local number = ZombRand(100);
				--local condition = Shared.getModData(ArrowItem).condition;
				--if condition == nil then ArrowItem:getCondition(); end
				local condition = ArrowItem:getCondition();
				if number <= (100/(ArrowItem:getConditionLowerChance()*20)) then condition = condition - 1; end
				--ArrowItem:getModData().MBAOcondition = condition;
				ArrowItem:setCondition(condition);
				if ArrowItem:getFullType() == "MandelaBowAndArrow.MandelaArrowBlank" then
					Shared.SetArrowName(ArrowItem);
				end
			end
			--player:getInventory():Remove(ArrowItem);
		end
		local ArrowNumber = modData.MandelaBowAndArrowArrowNumber;
		if ArrowNumber > 1 then
			modData.MandelaBowAndArrowQueuedForRemoval[i] = modData.MandelaBowAndArrowQueuedForRemoval[ArrowNumber];
			modData.MandelaBowAndArrowArrowItem[i] = modData.MandelaBowAndArrowArrowItem[ArrowNumber];
			modData.MandelaBowAndArrowArrowXSpeed[i] = modData.MandelaBowAndArrowArrowXSpeed[ArrowNumber];
			modData.MandelaBowAndArrowArrowYSpeed[i] = modData.MandelaBowAndArrowArrowYSpeed[ArrowNumber];
			modData.MandelaBowAndArrowArrowZSpeed[i] = modData.MandelaBowAndArrowArrowZSpeed[ArrowNumber];
			modData.MandelaBowAndArrowArrowX[i] = modData.MandelaBowAndArrowArrowX[ArrowNumber];
			modData.MandelaBowAndArrowArrowY[i] = modData.MandelaBowAndArrowArrowY[ArrowNumber];
			modData.MandelaBowAndArrowArrowZ[i] = modData.MandelaBowAndArrowArrowZ[ArrowNumber];
			modData.MandelaBowAndArrowSquare[i] = modData.MandelaBowAndArrowSquare[ArrowNumber];
			modData.MandelaBowAndArrowTarget[i] = modData.MandelaBowAndArrowTarget[ArrowNumber];
			modData.MandelaBowAndArrowLeavingArrow[i] = modData.MandelaBowAndArrowLeavingArrow[ArrowNumber];
			modData.MandelaBowAndArrowInZombieAsAttachment[i] = modData.MandelaBowAndArrowInZombieAsAttachment[ArrowNumber];
			if modData.DistanceFlown then modData.DistanceFlown[i] = modData.DistanceFlown[ArrowNumber]; end
		end
		modData.MandelaBowAndArrowQueuedForRemoval[ArrowNumber] = false;
		modData.MandelaBowAndArrowArrowItem[ArrowNumber] = nil;
		modData.MandelaBowAndArrowArrowXSpeed[ArrowNumber] = nil;
		modData.MandelaBowAndArrowArrowYSpeed[ArrowNumber] = nil;
		modData.MandelaBowAndArrowArrowZSpeed[ArrowNumber] = nil;
		modData.MandelaBowAndArrowArrowX[ArrowNumber] = nil;
		modData.MandelaBowAndArrowArrowY[ArrowNumber] = nil;
		modData.MandelaBowAndArrowArrowZ[ArrowNumber] = nil;
		modData.MandelaBowAndArrowSquare[ArrowNumber] = nil;
		modData.MandelaBowAndArrowTarget[ArrowNumber] = nil;
		modData.MandelaBowAndArrowLeavingArrow[ArrowNumber] = nil;
		modData.MandelaBowAndArrowInZombieAsAttachment[ArrowNumber] = nil;
		if modData.DistanceFlown then modData.DistanceFlown[ArrowNumber] = nil; end
		modData.MandelaBowAndArrowArrowNumber = ArrowNumber - 1;
	end
end

--After a near-perfect aim is calculated, this decides some deviation from that aim.
function Client.getDeviation(player, skillLevel)
	if skillLevel == nil then skillLevel = 3 end
	local panic = player:getStats():getPanic() / 400;
	local drunkenness = player:getStats():getDrunkenness() / 25;
	local fatigue = player:getStats():getFatigue();
	fatigue = (fatigue - 0.75)*2; if fatigue < 0 then fatigue = 0; end
	local deviation1 = (ZombRand(40) - ZombRand(40) + ZombRand(40) - ZombRand(40) + ZombRand(40) - ZombRand(40))/10;
	local deviation2 = (ZombRand(40) - ZombRand(40) + ZombRand(40) - ZombRand(40) + ZombRand(40) - ZombRand(40))/10;
	deviation1 = deviation1 * ((1+panic)*(1+drunkenness)*(1+fatigue));
	deviation2 = deviation2 * ((1+panic)*(1+drunkenness)*(1+fatigue));
	if skillLevel > 0 then
		deviation1 = deviation1/1.35^skillLevel;
		deviation2 = deviation2/1.35^skillLevel;
	end
	return math.rad(deviation1), math.rad(deviation2);
end

--Works out the pitch and yaw to hit a moving target that does not change its velocity.
function Client.getMovingTargetAim(player, target, weaponOffset, missileSpeed)
	local modData = Shared.getModData(player);
	local playerX = player:getX();
	local playerY = player:getY();
	local targetX = modData.primaryTarget:getX();
	local targetY = modData.primaryTarget:getY();
	local targetExtrapolatedX = targetX;
	local targetExtrapolatedY = targetY;
	local targetZ = modData.primaryTarget:getZ();
	
	local gravity = 0.003;
	local pitch = math.rad(12);
	
	local yaw = (math.atan2(targetY-playerY, targetX-playerX));
	local missileX = (player:getX() + math.cos(yaw) * weaponOffset);
	local missileY = (player:getY() + math.sin(yaw) * weaponOffset);
	
	local zDifference = ((targetZ + 0.08)-player:getZ())*2;
	
	local distance = math.sqrt(((targetX-playerX)^2)+((targetY-playerY)^2)) - weaponOffset;
	if distance > 1 then pitch = (math.atan(((missileSpeed^2)-math.sqrt((missileSpeed^4)-(gravity*((gravity*(distance^2))+(2*zDifference*(missileSpeed^2))))))/(gravity*distance))); end
	local horizontalSpeed = missileSpeed * math.cos(pitch);
	
	
	--This method of trying to aim at a moving target is used, but it seems to work well enough.
	for i=1, 2, 1 do
		targetExtrapolatedX = targetX + ((modData.targetXSpeed / horizontalSpeed) * distance);
		targetExtrapolatedY = targetY + ((modData.targetYSpeed / horizontalSpeed) * distance);
		local distance = math.sqrt(((targetExtrapolatedX-playerX)^2)+((targetExtrapolatedY-playerY)^2)) - weaponOffset;
		if distance > 1 then pitch = (math.atan(((missileSpeed^2)-math.sqrt((missileSpeed^4)-(gravity*((gravity*(distance^2))+(2*zDifference*(missileSpeed^2))))))/(gravity*distance))); end
		horizontalSpeed = missileSpeed * math.cos(pitch);
		yaw = (math.atan2(targetExtrapolatedY-playerY, targetExtrapolatedX-playerX));
		missileX = (player:getX() + math.cos(yaw) * weaponOffset);
		missileY = (player:getY() + math.sin(yaw) * weaponOffset);
	end
	
	return pitch, yaw;
end

--A function for shooting an arrow.
function Client.shootArrow(player, modData, target)
	local weapon = player:getPrimaryHandItem();
	local weaponModData = Shared.getModData(weapon);
	local arrowSpeed = 0.25;
	local yaw = 0;
	local pitch = math.rad(12);
	
	if target ~= nil then
		pitch,yaw = Client.getMovingTargetAim(player, target, 0.9, arrowSpeed);
	else
		local targetX, targetY = ISCoordConversion.ToWorld(getMouseXScaled(), getMouseYScaled(), 0);
		targetX = targetX+1.5;
		targetY = targetY+1.5;
		yaw = (math.atan2(targetY-player:getY(), targetX-player:getX()));
	end
	
	local deviation1, deviation2 = Client.getDeviation(player, Client.getArcherySkill(player));
	if not weapon:getRecoilpad() then
		deviation1, deviation2 = deviation1 * 2, deviation2 * 2;
	end
	yaw = yaw + deviation1;
	pitch = pitch + deviation2;
	
	local ArrowX = (player:getX() + math.cos(yaw) * 0.9);
	local ArrowY = (player:getY() + math.sin(yaw) * 0.9);
	local ArrowZ = (player:getZ())+0.45;
	
	if tostring(ArrowX) == Shared.nan then
		print("Glitch in shooting arrow");
		print("arrow x y and z", ArrowX, ArrowY, ArrowZ);
		print("yaw and pitch", yaw, pitch);
		print("deviations 1 and 2", deviation1, deviation2);
		if target == nil then
			local targetX, targetY = ISCoordConversion.ToWorld(getMouseXScaled(), getMouseYScaled(), 0);
			targetX = targetX+1.5;
			targetY = targetY+1.5;
			print("target x and y", targetX, targetY);
		end
		print("player x and y", player:getX(), player:getY());
		player:Say("Glitch in shooting arrow. The debug log should have details");
	end
	 
	local ArrowNumber = modData.MandelaBowAndArrowArrowNumber + 1;
	modData.MandelaBowAndArrowArrowNumber = ArrowNumber;
	modData.MandelaBowAndArrowArrowX[ArrowNumber] = ArrowX;
	modData.MandelaBowAndArrowArrowY[ArrowNumber] = ArrowY;
	modData.MandelaBowAndArrowArrowZ[ArrowNumber] = ArrowZ;
	modData.MandelaBowAndArrowQueuedForRemoval[ArrowNumber] = false;
	modData.MandelaBowAndArrowInZombieAsAttachment[ArrowNumber] = false;
	modData.MandelaBowAndArrowTarget[ArrowNumber] = target;
	modData.DistanceFlown[ArrowNumber] = 0;
	
	local items = player:getInventory();
	--Shared.getModData(newArrow).condition = weaponModData.arrowCondition;
	local arrowData = weaponModData.arrowData;
	local condition = arrowData.condition;
	local arrowFullType = arrowData.fullType;
	local modDataCopy = arrowData.modData;
	local newArrow = items:AddItem(arrowFullType);
	newArrow:setCondition(condition);
	local arrowModData = newArrow:getModData();
	for i, v in pairs(modDataCopy) do
		arrowModData[v[1]] = v[2];
	end
	if arrowFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
		local attachmentFullType = arrowData.stockFullType;
		local factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
		newArrow:attachWeaponPart(factoryItem);
		if arrowData.canonFullType then
			attachmentFullType = arrowData.canonFullType;
			factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
			newArrow:attachWeaponPart(factoryItem);
		end
		if arrowData.recoilpadFullType then
			attachmentFullType = arrowData.recoilpadFullType;
			factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
			newArrow:attachWeaponPart(factoryItem);
		end
	end
	Shared.getModData(newArrow).stockFullType = arrowData.stockFullType;
	Shared.getModData(newArrow).canonFullType = arrowData.canonFullType;
	Shared.getModData(newArrow).recoilpadFullType = arrowData.recoilpadFullType;
	weaponModData.arrowData = nil;
	local Square = player:getCurrentSquare();
	local newArrowWorld = Square:AddWorldInventoryItem(newArrow,
		ArrowX - math.floor(ArrowX),
		ArrowY - math.floor(ArrowY),
		ArrowZ - math.floor(ArrowZ),
		false);
	modData.MandelaBowAndArrowSquare[ArrowNumber] = Square;
	modData.MandelaBowAndArrowCell[ArrowNumber] = getWorld():getCell();
	player:getInventory():Remove(newArrow);
	
	newArrowWorld:setWorldZRotation(yaw);
	if arrowFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
		Shared.SetArrowName(newArrow);
	end
	
	modData.MandelaBowAndArrowArrowItem[ArrowNumber] = newArrow;
	modData.MandelaBowAndArrowArrowXSpeed[ArrowNumber] = math.cos(yaw) * arrowSpeed * math.cos(pitch);
	modData.MandelaBowAndArrowArrowYSpeed[ArrowNumber] = math.sin(yaw) * arrowSpeed * math.cos(pitch);
	modData.MandelaBowAndArrowArrowZSpeed[ArrowNumber] = arrowSpeed * math.sin(pitch);
	local xp = 1 + (ZombRand(100)/100);
	Client.addArcheryXP(player, xp);
end

--This function is called often for each player.
function Client.onPlayerUpdate(player)
	--if not player:isGhostMode() then player:setGhostMode(true) end
	local weapon = player:getPrimaryHandItem();
	if weapon ~= nil then
		if Client.Bows[weapon:getFullType()] ~= nil then
			Client.setUpBow(player,weapon);
		end
	end
	if player:isLocalPlayer() then
		--The code is run on the player's computer, so it's open to hax.
		if Client.localPlayerObj == nil then Client.localPlayerObj = player end
		local modData = Shared.getModData(player);
		if modData.DistanceFlown == nil then Client.OnLoad(player); end
		if modData.MandelaBowAndArrowArrowNumber > 0 then
			local ArrowNumber = modData.MandelaBowAndArrowArrowNumber;
			--Loops through the table of the player's arrows, if there are any.
			for i=1,ArrowNumber do
				local ArrowItem = nil;
				local ArrowWorldItem = nil;
				if modData.MandelaBowAndArrowArrowItem == nil or modData.MandelaBowAndArrowArrowZSpeed == nil then
					ArrowItem = nil;
				else
					ArrowItem = modData.MandelaBowAndArrowArrowItem[i];
				end
				if ArrowItem == nil then
					print("ArrowItem is nil");
					--player:Say("ArrowItem is nil");
					modData.MandelaBowAndArrowQueuedForRemoval[i] = true;
				else
					local Collision = false;
					
					local ArrowX = modData.MandelaBowAndArrowArrowX[i];
					local ArrowY = modData.MandelaBowAndArrowArrowY[i];
					local ArrowZ = modData.MandelaBowAndArrowArrowZ[i];
					local ArrowCellZ = math.floor(ArrowZ);
					local ArrowXSpeed = modData.MandelaBowAndArrowArrowXSpeed[i];
					local ArrowYSpeed = modData.MandelaBowAndArrowArrowYSpeed[i];
					local ArrowZSpeed = modData.MandelaBowAndArrowArrowZSpeed[i];
					
					local gravity = 0.003;
					
					--Instead of moving the arrow the full distance, which could make it clip through zombies, it can move a fraction of the distance multiple times and check for collisions each time.
					local divisions = 2;
					for i2=1,divisions do
						if Collision == false then
							--ArrowZSpeed = ArrowZSpeed * ( 1 - 0.02);
							
							do
								local beforeX, beforeY, beforeZ = ArrowX, ArrowY, ArrowZ;
								ArrowX = ArrowX + (ArrowXSpeed/divisions);
								ArrowY = ArrowY + (ArrowYSpeed/divisions);
								ArrowZ = ArrowZ + ((ArrowZSpeed/2)/divisions);
								if (tostring(beforeX) ~= Shared.nan and tostring(beforeY) ~= Shared.nan and tostring(beforeZ) ~= Shared.nan) and (tostring(ArrowX) == Shared.nan or tostring(ArrowY) == Shared.nan or tostring(ArrowZ) == Shared.nan) then
									print("caught a number becoming nan");
									print(beforeX, beforeY, beforeZ);
									print(ArrowX, ArrowY, ArrowZ);
									print(ArrowXSpeed, ArrowYSpeed, ArrowZSpeed);
									print(i, ArrowNumber, i2);
								end
							end
							
							local can_damage = true;
							if ArrowItem:getRecoilpad() and Client.ArrowPartData[ArrowItem:getRecoilpad():getFullType()] ~= nil and Client.ArrowPartData[ArrowItem:getRecoilpad():getFullType()].fluflu == true then
								modData.DistanceFlown[i] = modData.DistanceFlown[i] + math.sqrt(ArrowXSpeed^2 + ArrowYSpeed^2)
								if modData.DistanceFlown[i] > 8 then
									can_damage = false
									ArrowXSpeed = ArrowXSpeed * ( 1 - (0.01 / divisions));
									ArrowYSpeed = ArrowYSpeed * ( 1 - (0.01 / divisions));
								end
							end
							
							ArrowZSpeed = ArrowZSpeed - (gravity / divisions);
							
							--local Cell = IsoMetaGrid:
							
							local Cell = getWorld():getCell();
							local Square = Cell:getOrCreateGridSquare(ArrowX,ArrowY,ArrowZ);
							
							local arrowCondition = ArrowItem:getCondition();
							if ArrowItem:getWorldItem() ~= nil then
								ArrowItem:getWorldItem():getSquare():transmitRemoveItemFromSquare(ArrowItem:getWorldItem());
								ArrowItem:getWorldItem():removeFromSquare();
							end
							
							--gets the target's cell, probably not needed any more because the Java works differently now so you don't need a reference to the cell that contains the square to get a reference to the square, it seems.
							local targetCell = nil;
							if modData.MandelaBowAndArrowTarget[i] ~= nil then 
								targetCell = modData.MandelaBowAndArrowTarget[i]:getCell();
							end
							--gets squares adjacent to the arrow's current square
							local upSquare = Cell:getOrCreateGridSquare(ArrowX,ArrowY,ArrowZ+1);
							if Square == nil and targetCell ~= nil then
								Square = targetCell:getOrCreateGridSquare(ArrowX,ArrowY,ArrowZ);
								upSquare = targetCell:getOrCreateGridSquare(ArrowX,ArrowY,ArrowCellZ+1);
							end
							local sideSquare = Cell:getOrCreateGridSquare(ArrowX+1,ArrowY,ArrowZ);
							if sideSquare == nil and targetCell ~= nil then
								sideSquare = targetCell:getOrCreateGridSquare(ArrowX+1,ArrowY,ArrowZ);
							end
							local backSquare = Cell:getOrCreateGridSquare(ArrowX,ArrowY+1,ArrowZ);
							if backSquare == nil and targetCell ~= nil then
								backSquare = targetCell:getOrCreateGridSquare(ArrowX,ArrowY+1,ArrowZ);
							end
							local otherSideSquare = Cell:getOrCreateGridSquare(ArrowX-1,ArrowY,ArrowZ);
							if otherSideSquare == nil and targetCell ~= nil then
								otherSideSquare = targetCell:getOrCreateGridSquare(ArrowX-1,ArrowY,ArrowZ);
							end
							local otherBackSquare = Cell:getOrCreateGridSquare(ArrowX,ArrowY-1,ArrowZ);
							if otherBackSquare == nil and targetCell ~= nil then
								otherBackSquare = targetCell:getOrCreateGridSquare(ArrowX,ArrowY-1,ArrowZ);
							end
							
							local lastSquare = modData.MandelaBowAndArrowSquare[i];
							
							if Square ~= nil then
								if ArrowZ < ArrowCellZ then
									local Square2 = getWorld():getCell():getOrCreateGridSquare(ArrowX,ArrowY,ArrowCellZ);
									if Square2 == nil and targetCell ~= nil then
										Square2 = targetCell:getOrCreateGridSquare(ArrowX,ArrowY,ArrowCellZ);
									end
									if Square2 ~= nil then
										if Square2:isSolidFloor() then Collision = true; end
									end
								end
								
								lastXoff = ArrowX - math.floor(ArrowX);
								lastYoff = ArrowY - math.floor(ArrowY);
								lastZoff = ArrowZ - math.floor(ArrowZ);
								if ArrowZ < 0.001 then lastZoff = 0; end

								if ArrowZ < 0 then
									ArrowZ = 0;
									Collision = true;
								else
								--[[
									local movingObjects = Square:getObjects();
									for ii=0, movingObjects:size()-1 do
										if(player:getZ() < 3) then
											if ( (movingObjects:get(ii):getWaterAmount() > 0) 
											or (IsIn(tostring(movingObjects:get(ii):getType()),"stair")) 
											or (tostring(movingObjects:get(ii):getType()) == "wall") 
											or (movingObjects:get(ii):getObjectName() == "Tree") 
											or (movingObjects:get(ii):getObjectName() == "Door") 
											or (movingObjects:get(ii):getObjectName() == "Window") )
											then
												if(movingObjects:get(ii):getWaterAmount() > 999) then HitWater = true; end
												CObject = movingObjects:get(ii);
												Collision = true;
												Square:playSound("BatHit");
												addSound(player, ArrowX, ArrowY, ArrowZ, 10, 2);
											end
										end
									end]]--
									local movingObjects = Square:getObjects();
									for ii=0, movingObjects:size()-1 do
										if(player:getZ() < 3) then
											local collision = false;
											local wall = false;
											if (IsIn(tostring(movingObjects:get(ii):getType()),"stair")) then collision = true; end
											if (movingObjects:get(ii):getObjectName() == "Tree") and lastXoff > 0.25 and lastXoff < 0.75 and lastYoff > 0.25 and lastYoff < 0.75 then collision = true; end
											if ((tostring(movingObjects:get(ii):getType()) == "wall") 
											or (movingObjects:get(ii):getObjectName() == "Door") 
											or (movingObjects:get(ii):getObjectName() == "Window")) then
												--if movingObjects:get(ii):isHoppable() and lastZoff < 0.4 then
												--end
												if (
													(
														(Square ~= lastSquare) and (((lastXoff < 0.15/divisions) or (lastYoff < 0.15/divisions)) and lastSquare:isBlockedTo(Square))
													)
													or (
														(Square == lastSquare) and
															(
																((lastXoff < 0.15/divisions) and (lastSquare:isBlockedTo(otherSideSquare)))
																or ((lastYoff < 0.15/divisions) and (lastSquare:isBlockedTo(otherBackSquare)))
															)
														)
													) then collision = true; wall = true; end
											end
											if collision then
												--player:Say("Square collision " .. tostring(movingObjects:get(ii):isHoppable()));
												CObject = movingObjects:get(ii);
												Collision = true;
												Square:playSound(Client.Sounds.HitTile);
												addSound(player, ArrowX, ArrowY, ArrowZ, 10, 2);
												
												if wall and ArrowXSpeed > 0 and lastXoff < 0.15/divisions and ArrowXSpeed^2 > ArrowYSpeed^2 and otherSideSquare ~= nil then
													Square = otherSideSquare; 
													ArrowX = math.floor(ArrowX) - 0.05;
													lastXoff = ArrowX - math.floor(ArrowX);
													--player:Say("Adjusting on X");
												end
												if wall and ArrowYSpeed > 0 and lastYoff < 0.15/divisions and ArrowYSpeed^2 > ArrowXSpeed^2 and otherBackSquare ~= nil then
													Square = otherBackSquare; 
													ArrowY = math.floor(ArrowY) - 0.05;
													lastYoff = ArrowY - math.floor(ArrowY);
													--player:Say("Adjusting on Y");
												end
											end
										end
									end
									if sideSquare ~= nil then
										movingObjects = sideSquare:getObjects();
										for ii=0, movingObjects:size()-1 do
											if(player:getZ() < 3) then
												local collision = false;
												if (tostring(movingObjects:get(ii):getType()) == "wall") 
												or (movingObjects:get(ii):getObjectName() == "Door") 
												or (movingObjects:get(ii):getObjectName() == "Window") then
													if (lastXoff > 1-(0.15/divisions)) and ((lastSquare ~= Square and lastSquare:isBlockedTo(Square)) or Square:isBlockedTo(sideSquare)) then collision = true; end
												end
												if collision then
													--player:Say("sideSquare collision " .. tostring(movingObjects:get(ii):isHoppable()));
													CObject = movingObjects:get(ii);
													Collision = true;
													Square:playSound(Client.Sounds.HitTile);
													addSound(player, ArrowX, ArrowY, ArrowZ, 10, 2);
													
													if ArrowXSpeed < 0 and lastXoff > 1-(0.15/divisions) and ArrowXSpeed^2 > ArrowYSpeed^2 then
														Square = sideSquare; 
														ArrowX = math.floor(ArrowX) + 1.05;
														lastXoff = ArrowX - math.floor(ArrowX);
														--player:Say("Adjusting on X 2");
													end
												end
											end
										end
									end
									if backSquare ~= nil then
										movingObjects = backSquare:getObjects();
										for ii=0, movingObjects:size()-1 do
											if(player:getZ() < 3) then
												local collision = false;
												if (tostring(movingObjects:get(ii):getType()) == "wall") 
												or (movingObjects:get(ii):getObjectName() == "Door") 
												or (movingObjects:get(ii):getObjectName() == "Window") then
													if (lastYoff > 1-(0.15/divisions)) and ((lastSquare ~= Square and lastSquare:isBlockedTo(Square)) or Square:isBlockedTo(backSquare)) then collision = true; end
												end
												if collision then
													--player:Say("backSquare collision " .. tostring(movingObjects:get(ii):isHoppable()));
													CObject = movingObjects:get(ii);
													Collision = true;
													Square:playSound(Client.Sounds.HitTile);
													addSound(player, ArrowX, ArrowY, ArrowZ, 10, 2);
													
													if ArrowYSpeed < 0 and lastYoff > 1-(0.15/divisions) and ArrowYSpeed^2 > ArrowXSpeed^2 then
														Square = backSquare; 
														ArrowY = math.floor(ArrowY) + 1.05;
														lastYoff = ArrowY - math.floor(ArrowY);
														--player:Say("Adjusting on Y 2");
													end
												end
											end
										end
									end
								end
								
								if not Collision then
									if ArrowZ - math.floor(ArrowZ) <= 0.595 then
										Client.ArrowHitZombie(ArrowX-0.33,ArrowY-0.33,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX,ArrowY,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX+0.33,ArrowY+0.33,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX+0.33,ArrowY,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX,ArrowY+0.33,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX-0.33,ArrowY,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX,ArrowY-0.33,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX+0.33,ArrowY-0.33,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
										Client.ArrowHitZombie(ArrowX-0.33,ArrowY+0.33,ArrowZ,player,ArrowItem,i,modData,ArrowX,ArrowY,ArrowZ,can_damage);
									end
								end
								
								if not modData.MandelaBowAndArrowInZombieAsAttachment[i] then
									if ArrowZ < ArrowCellZ then
										if upSquare ~= nil then
											ArrowWorldItem = upSquare:AddWorldInventoryItem(ArrowItem,lastXoff,lastYoff,lastZoff-1,false);
										else
											local groundSquare = Cell:getOrCreateGridSquare(ArrowX,ArrowY,0);
											if Square == nil and targetCell ~= nil then
												groundSquare = targetCell:getOrCreateGridSquare(ArrowX,ArrowY,0);
											end
											ArrowWorldItem = groundSquare:AddWorldInventoryItem(ArrowItem,lastXoff,lastYoff,ArrowZ,false);
											--[[
											local scanning = true;
											for i=0,math.floor(ArrowZ+1) do
												if scanning then
													local scanZ = math.floor(ArrowZ+1) - i;
													local scanSquare = Cell:getGridSquare(ArrowX,ArrowY,scanZ);
													if scanSquare == nil and targetCell ~= nil then
														scanSquare = targetCell:getGridSquare(ArrowX,ArrowY,scanZ);
													end
													if scanSquare ~= nil then
														scanning = false;
														scanSquare:AddWorldInventoryItem(ArrowItem,lastXoff,lastYoff,lastZoff-i);
													end
												end
											end]]--
										end
									else
										ArrowWorldItem = Square:AddWorldInventoryItem(ArrowItem,lastXoff,lastYoff,lastZoff,false);
									end
								end
							else
								--modData.MandelaBowAndArrowQueuedForRemoval[i] = true;
								print("Bow and Arrow mod Error: Square is nil (2) ", i, i2);
								print("ArrowX, ArrowY, ArrowZ: ", ArrowX, ArrowY, ArrowZ);
								print("player:getX(), player:getY(), player:getZ(): ", player:getX(), player:getY(), player:getZ());
								print("Cell, targetCell", Cell, targetCell);
								if Cell then print("Cell:getGridSquare(ArrowX,ArrowY,ArrowZ)", Cell:getGridSquare(ArrowX,ArrowY,ArrowZ)) end
								if targetCell then print("targetCell:getGridSquare(ArrowX,ArrowY,ArrowZ)", targetCell:getGridSquare(ArrowX,ArrowY,ArrowZ)) end
								--player:Say("Square is nil");
								if tostring(modData.MandelaBowAndArrowArrowX[i]) == Shared.nan then
									modData.MandelaBowAndArrowQueuedForRemoval[i] = true;
									print("Removing glitched arrow");
									player:Say("Removing glitched arrow. The debug log may have details.");
								end
							end
							
							if Collision then
								modData.MandelaBowAndArrowLeavingArrow[i] = true;
								modData.MandelaBowAndArrowQueuedForRemoval[i] = true;
							else
								modData.MandelaBowAndArrowArrowX[i] = ArrowX;
								modData.MandelaBowAndArrowArrowY[i] = ArrowY;
								modData.MandelaBowAndArrowArrowZ[i] = ArrowZ;
								modData.MandelaBowAndArrowArrowXSpeed[i] = ArrowXSpeed;
								modData.MandelaBowAndArrowArrowYSpeed[i] = ArrowYSpeed;
								modData.MandelaBowAndArrowArrowZSpeed[i] = ArrowZSpeed;
								modData.MandelaBowAndArrowSquare[i] = Square;
							end
						end
						
						if (ArrowWorldItem ~= nil) and (not modData.MandelaBowAndArrowQueuedForRemoval[i]) then
							ArrowWorldItem:setWorldZRotation(math.deg(math.atan2(ArrowYSpeed, ArrowXSpeed)));
						end
					end
				end
			end
			
			for i=ArrowNumber, 1, -1 do
				if modData.MandelaBowAndArrowQueuedForRemoval[i] == true then
					--print("removal queue: " .. tostring(i));
					--modData.MandelaBowAndArrowQueuedForRemoval[i] = false;
					local ArrowX = modData.MandelaBowAndArrowArrowX[i];
					local ArrowY = modData.MandelaBowAndArrowArrowY[i];
					local ArrowZ = modData.MandelaBowAndArrowArrowZ[i];
					--local Square = getWorld():getCell():getGridSquare(ArrowX,ArrowY,ArrowZ);
					local Square = modData.MandelaBowAndArrowSquare[i];
					Client.removeShotArrow(player,i,Square,ArrowX,ArrowY,ArrowZ);
				end
			end
		end
	end
end

function Client.OnLoad(player) --fails on load
	--local player = getPlayer();
	local modData = Shared.getModData(player);
	modData.MandelaBowAndArrowArrowNumber = 0;
	modData.MandelaBowAndArrowQueuedForRemoval = {};
	modData.MandelaBowAndArrowArrowItem = {};
	modData.MandelaBowAndArrowArrowXSpeed = {};
	modData.MandelaBowAndArrowArrowYSpeed = {};
	modData.MandelaBowAndArrowArrowZSpeed = {};
	modData.MandelaBowAndArrowArrowX = {};
	modData.MandelaBowAndArrowArrowY = {};
	modData.MandelaBowAndArrowArrowZ = {};
	modData.MandelaBowAndArrowSquare = {};
	modData.MandelaBowAndArrowCell = {};
	modData.MandelaBowAndArrowTarget = {};
	modData.MandelaBowAndArrowLeavingArrow = {};
	modData.MandelaBowAndArrowInZombieAsAttachment = {};
	modData.DistanceFlown = {};
	Client.checkArcherySkill(player);
	
	local weapon = player:getPrimaryHandItem();
	if weapon ~= nil then
		if Client.isMandelaBow(weapon:getFullType()) then
			Shared.getModData(weapon).modelVariantNumber = nil;
		end
	end
end

function Client.OnCreateSurvivor(Survivor) --fails
	--local items = Survivor:getInventory();
	
	local modData = Shared.getModData(Survivor);
	modData.MandelaBowAndArrowArrowNumber = 0;
	modData.MandelaBowAndArrowQueuedForRemoval = {};
	modData.MandelaBowAndArrowArrowItem = {};
	modData.MandelaBowAndArrowArrowXSpeed = {};
	modData.MandelaBowAndArrowArrowYSpeed = {};
	modData.MandelaBowAndArrowArrowZSpeed = {};
	modData.MandelaBowAndArrowArrowX = {};
	modData.MandelaBowAndArrowArrowY = {};
	modData.MandelaBowAndArrowArrowZ = {};
	modData.MandelaBowAndArrowSquare = {};
	modData.MandelaBowAndArrowCell = {};
	modData.MandelaBowAndArrowTarget = {};
	modData.MandelaBowAndArrowLeavingArrow = {};
	modData.MandelaBowAndArrowInZombieAsAttachment = {};
	modData.DistanceFlown = {};
	Client.checkArcherySkill(Survivor);
end

--A function to call on attack, which checks whether or not to use this mod's attack function that shoots arrows.
Client.attackHook = function(character, chargeDelta, weapon)
	if (Client.isMandelaBow(weapon:getFullType()) and (((Shared.versionNumber == nil or Shared.versionNumber >= 41.60 or Shared.versionNumber <= 40) and (not character:isDoShove())) or ((Shared.versionNumber ~= nil and Shared.versionNumber < 41.60) and (not character:isShoving())))) then
		local modData = Shared.getModData(character);
		--[[
		if Shared.getModData(weapon).isDrawn then
			ISTimedActionQueue.clear(character)
			if character:isAttackStarted() then return; end
			if weapon:isRanged() and not character:isShoving() then
				if ISMBAReloadBowAction.canShoot(weapon) then
					character:playSound(weapon:getSwingSound());
					AddWorldSound(character, weapon:getSoundRadius(), weapon:getSoundVolume());
					character:DoAttack(0);
				else
					character:DoAttack(0);
					character:setRangedWeaponEmpty(true);
				end
			else
				ISTimedActionQueue.clear(character)
				if(chargeDelta == nil) then
					character:DoAttack(0);
				else
					character:DoAttack(chargeDelta);
				end
			end
		end]]--
		
		if Shared.getModData(weapon).isDrawn then
			ISTimedActionQueue.clear(character)
			if character:isAttackStarted() then return; end
			if ISMBAReloadBowAction.canShoot(weapon) then
				local missileSpeed = Client.Bows[weapon:getFullType()].speed;
				Shared.modDataCompatibility(weapon);
				if character:isLocalPlayer() then
					if modData.primaryTarget ~= nil then
						Client.shootArrow(character, modData, modData.primaryTarget)
						--Shared.getModData(weapon).modelVariantNumber = 4;
						--MandelaBowAndArrow.shootArrowAtMovingTarget(character, weapon, modData.primaryTarget, missileSpeed);
					else
						Client.shootArrow(character, modData)
						--Shared.getModData(weapon).modelVariantNumber = 4;
						--[[
						local targetX, targetY = ISCoordConversion.ToWorld(getMouseXScaled(), getMouseYScaled(), 0);
						targetX = targetX+1.5;
						targetY = targetY+1.5;
						local targetZ = character:getZ();
						MandelaBowAndArrow.shootArrowAtPoint(character, weapon, targetX, targetY, targetZ, missileSpeed)]]--
					end
				end
				Shared.getModData(weapon).modelVariantNumber = 4;
				weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() - weapon:getAmmoPerShoot());
				character:playSound(weapon:getSwingSound());
				--character:addWorldSoundUnlessInvisible(weapon:getSoundRadius(), weapon:getSoundVolume(), false);
				local soundVolume = Client.Bows[weapon:getFullType()].soundVolume or 1;
				local soundRadius = Client.Bows[weapon:getFullType()].soundRadius or 4;
				character:addWorldSoundUnlessInvisible(soundRadius, soundVolume, false);
				--character:playSound(weapon:getSwingSound());
				--AddWorldSound(character, weapon:getSoundRadius(), weapon:getSoundVolume());
				--Square:playSound("BatHit");
				--addSound(player, ArrowX, ArrowY, ArrowZ, 10, 2);
				--character:playSound(weapon:getSwingSound());
				--character:playSound("BatSwing");
				--character:getSquare():playSound("BatSwing");
				--AddWorldSound(character, weapon:getSoundRadius(), weapon:getSoundVolume());
				if weapon:getCanon() then
					weapon:detachWeaponPart(weapon:getCanon());
				end
				if weapon:getStock() then
					weapon:detachWeaponPart(weapon:getStock());
				end
				if weapon:getRecoilpad() then
					weapon:detachWeaponPart(weapon:getRecoilpad());
				end
				character:resetEquippedHandsModels();
				Shared.getModData(weapon).isDrawn = false;
				Shared.getModData(character).hasShot = true;
				--character:getSquare():playSound("BladeHit");
			else
				character:setRangedWeaponEmpty(true);
			end
		end
		return true
	else
		return false
	end
end

do
Hook.Attack.Remove(ISReloadWeaponAction.attackHook); --Removes what by default is the current attack function from the attack hook
local original_attackHook = ISReloadWeaponAction.attackHook; --Also stores it in a local variable
ISReloadWeaponAction.attackHook = function(...) --Makes a new function that replaces the original
	if not Client.attackHook(...) then --Which calls the custom function above.
		original_attackHook(...); --And if it doesn't return true, runs the original function instead.
	end
end
Hook.Attack.Add(ISReloadWeaponAction.attackHook); --Adds this new function to the attack hook.
end

------------------------------------------------------------------------

--Does things
function Client.setUpBow(player,bow)
	--local player = getPlayer();
	local playerModData = Shared.getModData(player);
	local weaponModData = Shared.getModData(bow);
	if bow:getFireRange() ~= 0 then bow:setFireRange(0) end
	if bow:getMaxRange() ~= 0 then bow:setMaxRange(0) end
	
	if player:isAiming() then
		if playerModData.aiming ~= true then
			playerModData.aiming = true;
		end
		if not weaponModData.isDrawn then
			drawnAmount = weaponModData.MBAOdrawnAmount;
			if drawnAmount == nil then drawnAmount = 0; end
			drawnAmount = drawnAmount + getGameTime():getMultiplier();
			--should change to drawnAmount = drawnAmount + getGameTime():getTimeDelta();
			if drawnAmount < 15 then weaponModData.MBAOdrawnAmount = drawnAmount; else
				weaponModData.MBAOdrawnAmount = 0;
				weaponModData.isDrawn = true;
				Client.SetBowAndArrowModel(player, bow, 2);
			end
		end
	else
		if playerModData.hasShot == true then
			playerModData.hasShot = false;
		end
		if playerModData.aiming == true then
			playerModData.aiming = false;
			weaponModData.MBAOdrawnAmount = 0;
			weaponModData.isDrawn = false;
			Client.SetBowAndArrowModel(player, bow, 1);
		end
	end
	if player:getPrimaryHandItem() == bow then
		if bow:getCondition() == 0 then
			local bow = player:getInventory():AddItem(bow:getFullType() .. "Unstrung");
			player:setPrimaryHandItem(nil);
			player:setPrimaryHandItem(bow);
			player:setSecondaryHandItem(bow);
			player:getInventory():Remove(bow);
			player:resetEquippedHandsModels();
		elseif not playerModData.aiming then
			Client.SetBowAndArrowModel(player, bow, 1);
		end
	end
	if player:getPrimaryHandItem() ~= bow then
		Client.SetBowAndArrowModel(player, bow, 0);
	end
end

--OnEquipPrimary
function Client.OnEquipPrimary(player, equipedItem)
	local inventory = player:getInventory();
	local bows = {};
	for bowType,v in pairs(Client.Bows) do
		local items = inventory:getItemsFromFullType(bowType);
		if items ~= nil and (not items:isEmpty()) then
			for i = 1, items:size() do
				local bow = items:get(i-1);
				if bow:getCondition() > 0 then
					bows[#bows+1] = bow;
				end
			end
		end
	end
	for i,bow in ipairs(bows) do
		Client.UnloadArrow(player, bow);
		Client.setUpBow(player,bow);
	end
end

--OnEquipSecondary
function Client.OnEquipSecondary(player,item)
	Client.OnEquipPrimary(player,item);
end

--FirearmsB41Patch uses ISReloadWeaponAction.attackHookFirearms instead of ISReloadWeaponAction.attackHook, so it needs a different compatibility function for it. Also, the function runs in OnGameBoot, which should be after all the lua has loaded.
Client.FirearmsB41Patch = function()
	if ISReloadWeaponAction.attackHookFirearms ~= nil then
		print("OnGameBoot: Bow and Arrow mod patching ISReloadWeaponAction.attackHookFirearms of B41 Firearms");
		local original_attackHookFirearms = ISReloadWeaponAction.attackHookFirearms;
		Hook.Attack.Remove(original_attackHookFirearms);
		ISReloadWeaponAction.attackHookFirearms = function(character, chargeDelta, weapon)
			if (Client.isMandelaBow(weapon:getFullType()) and (((Shared.versionNumber == nil or Shared.versionNumber >= 41.60 or Shared.versionNumber <= 40) and (not character:isDoShove())) or ((Shared.versionNumber ~= nil and Shared.versionNumber < 41.60) and (not character:isShoving())))) then
				Client.attackHook(character, chargeDelta, weapon);
			else
				original_attackHookFirearms(character, chargeDelta, weapon);
			end
		end
		Hook.Attack.Add(ISReloadWeaponAction.attackHookFirearms);
	end
end

function Client.OnGameBoot()
	--[[
	if Client.Shared.versionNumber < 41.51 then
		TraitFactory.addTrait("MBAOarcher", getText("UI_trait_archer"), 4, getText("UI_trait_archerdesc"), false)
	else
		local archer = TraitFactory.addTrait("MBAarcher2", getText("UI_trait_archer"), 4, getText("UI_trait_archerdesc2"), false);
		archer:addXPBoost(Perks.Archery, 4);
	end]]--
	Client.FirearmsB41Patch();
	local archer = TraitFactory.addTrait("MBAOarcher", getText("UI_trait_archer"), 4, getText("UI_trait_archerdesc"), false)
	archer:addXPBoost(Perks.Archery, 2);
end

function Client.OnZombieDead(zombie)
	if ((zombie:hasModData()) and (zombie:getModData().MandelaBowAndArrow ~= nil) and (zombie:getModData().MandelaBowAndArrow.arrowTable ~= nil)) then
		local modData = Shared.getModData(zombie);
		if modData.yeet then
			modData.yeet = false;
		else
			for i,arrowData in pairs(modData.arrowTable) do
				local condition = arrowData.condition;
				local arrowFullType = arrowData.fullType;
				local modDataCopy = arrowData.modData;
				local newArrow = InventoryItemFactory.CreateItem(arrowFullType);
				zombie:getInventory():AddItem(newArrow);
				newArrow:setCondition(condition);
				local arrowModData = newArrow:getModData();
				for i, v in pairs(modDataCopy) do
					arrowModData[v[1]] = v[2];
				end
				if arrowFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
					local attachmentFullType = arrowModData.MandelaBowAndArrow.stockFullType;
					local factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
					newArrow:attachWeaponPart(factoryItem);
					if arrowModData.MandelaBowAndArrow.canonFullType then
						attachmentFullType = arrowModData.MandelaBowAndArrow.canonFullType;
						factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
						newArrow:attachWeaponPart(factoryItem);
					end
					if arrowModData.MandelaBowAndArrow.recoilpadFullType then
						attachmentFullType = arrowModData.MandelaBowAndArrow.recoilpadFullType;
						factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
						newArrow:attachWeaponPart(factoryItem);
					end
					Shared.SetArrowName(newArrow);
				end
			end
			modData.arrowTable = nil;
		end
	end
end

--This is for the after the right-click menu has loaded.
function Client.OnFillMenu(player, context, items)
	local playerObj = getSpecificPlayer(player)
	local testItem = nil;
	for i,v in ipairs(items) do
		testItem = v;
		if not instanceof(v, "InventoryItem") then
			testItem = v.items[1];
		end
	end
	if (testItem:getType() == "MandelaBowStave" or testItem:getType() == "MandelaBowStave2") and playerObj:getPerkLevel(Perks.Woodwork) > 1 then
		context:addOption(getText("ContextMenu_MBA_Make_Bow"), testItem, ISInventoryPaneContextMenu.MBAOcarveBowStave, playerObj);
	end
	
	--It looks for options in the menu to remove attachments from a modular arrow with a screwdriver, and removes them from the list.
	--It also removes the options onUnloadBulletsFromFirearm and onLoadBulletsIntoFirearm.
	local removeUpgradeName = getText("ContextMenu_Remove_Weapon_Upgrade");
	for i=#context.options, 1, -1 do
		local option = context.options[i];
		if option.name == removeUpgradeName then
			local breaking = false;
			for i2,target in ipairs(option.target) do
				if type(target) == "table" then
					for i3,item in ipairs(target.items) do
						if Client.isMandelaBow(item:getFullType(), 1)
						or item:getFullType() == "MandelaBowAndArrow.MandelaArrowBlank" then--or item:getFullType() == "MandelaBowAndArrow.MandelaArrowBlank" then
							table.remove(context.options, i); -- There's that nice table reusing, and then here there's just a table.remove. :/
							context.numOptions = context.numOptions - 1;
							context:calcHeight();
							context:setWidth(context:calcWidth());
							breaking = true;
							break;
						end
					end
				else
					if Client.isMandelaBow(target:getFullType(), 1)
					or target:getFullType() == "MandelaBowAndArrow.MandelaArrowBlank" then
						table.remove(context.options, i);
						context.numOptions = context.numOptions - 1;
						context:calcHeight();
						context:setWidth(context:calcWidth());
						break;
					end
				end
				if breaking then break end
			end
		elseif (option.onSelect == ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm and Client.isMandelaBow(option.param1:getFullType(), 0))
		or (option.onSelect == ISInventoryPaneContextMenu.onLoadBulletsIntoFirearm and Client.isMandelaBow(option.param1:getFullType(), 0)) then
			table.remove(context.options, i);
			context.numOptions = context.numOptions - 1;
			context:calcHeight();
			context:setWidth(context:calcWidth());
		--[[elseif option.onSelect == ISInventoryPaneContextMenu.onRackGun and MandelaBowAndArrow.isMandelaBow(option.param1:getFullType(), 0) then
			table.remove(context.options, i);
			context.numOptions = context.numOptions - 1;
			context:calcHeight();
			context:setWidth(context:calcWidth());]]--
		end
	end
	
	Client.CustomRecipesMenu(player, context, items)
end

--This function runs if you click the option to carge the bow stave. Looking at this, it really should require a woodworking tool but it doesn't seem to.
ISInventoryPaneContextMenu.MBAOcarveBowStave = function(item, playerObj)
	Shared.modDataCompatibility(item);
	if item:getContainer() ~= playerObj:getInventory() then
		ISTimedActionQueue.add(ISInventoryTransferAction:new(playerObj, item, item:getContainer(), playerObj:getInventory(), nil));
	end
	ISTimedActionQueue.add(ISMBAcarveBowStaveAction:new(playerObj, item));
end

--[[
local MBAOHolsterRightQuiver = {
	type = "MBAOHolsterRightQuiver",
	name = "Right Hip Quiver",
	animset = "holster right",
	--animset = "belt right",
	attachments = {
		MBAOHolsterRightQuiver = "Belt Right",
	},
}]]--

--ISHotbarAttachDefinition[2].attachments.MBAOHolsterRightQuiver = "Belt Right";

--Some render code. It waits until prerender to replace the render function with a new one. The new one runs custom code if conditions are met, otherwise runs the original. Based originally on code from a firearm mod that based it on the game's Java, or close to that.
do
	local borderLocked = false;
	local ToolTipStats = {x = 0, y = 0, w = 0, h = 0}
	
	--This code is because if you want to add more text to the tooltip, it should have a bigger rectangle.
	local drawRectBorder = ISToolTipInv.drawRectBorder;
	function ISToolTipInv:drawRectBorder(x, y, w, h, a, r, g, b)
		if borderLocked then
			ToolTipStats.x = math.min(x, ToolTipStats.x);
			ToolTipStats.x = math.min(y, ToolTipStats.y);
			ToolTipStats.w = math.max(w, ToolTipStats.w);
			ToolTipStats.h = math.max(h, ToolTipStats.h);
		else
			drawRectBorder(self, x, y, w, h, a, r, g, b)
		end
	end
	
	local InventoryItemFactory = InventoryItemFactory;
	local original_prerender = ISToolTipInv.prerender;
	function ISToolTipInv:prerender()
		original_prerender(self);
		local original_render = ISToolTipInv.render;
		function ISToolTipInv:render()
			local itemType = self.item:getType();
			if not (itemType == "MandelaArrowShaft"
			or itemType == "MandelaBowString"
			or itemType == "MandelaBowString2"
			or itemType == "MandelaBowStave"
			or itemType == "MandelaBowStave2"
			or itemType == "MandelaArrowBlank"
			or (itemType == "MandelaArrowWoodDucttapeIronTaped" and ((self.item:hasModData()) and (self.item:getModData().MandelaBowAndArrow ~= nil) and (self.item:getModData().MandelaBowAndArrow.note ~= nil)))
			or Client.isMandelaBow(self.item:getFullType())) then
				borderLocked = false;
				original_render(self);
			else
				
				--Removes them to avoid them being listed in the tooltip. They are added again later.
				local canon, stock, recoilpad;
				if instanceof(self.item, "HandWeapon") then
					if self.item:getCanon() then
						canon = self.item:getCanon():getFullType();
						self.item:detachWeaponPart(self.item:getCanon());
					end
					if self.item:getStock() then
						stock = self.item:getStock():getFullType();
						self.item:detachWeaponPart(self.item:getStock());
					end
					if self.item:getRecoilpad() then
						recoilpad = self.item:getRecoilpad():getFullType();
						self.item:detachWeaponPart(self.item:getRecoilpad());
					end
				end
				
				borderLocked = true;
				ToolTipStats.x = 0; ToolTipStats.y = 0; ToolTipStats.w = 0; ToolTipStats.h = 0;
				original_render(self);
				borderLocked = false;
				
				local lh = getTextManager():getFontFromEnum(font_name):getLineHeight();
				local original_height = ToolTipStats.h;
				local original_width = ToolTipStats.w;
				local width = original_width;
				local extraLines = 0;
				local extraText = {};
				local text = nil;
				
				local modData = Shared.getModData(self.item);
				
				if modData.note ~= nil then
					text = modData.note;
				end
				
				if itemType == "MandelaArrowShaft" or itemType == "MandelaBowString" or itemType == "MandelaBowString2" then
					if width < 220 then width = 220; end
					extraLines = extraLines + 1;
				elseif itemType == "MandelaBowStave" or itemType == "MandelaBowStave2" then
					if width < 220 then width = 220;end
					extraLines = extraLines + 1;
				end
				
				if text ~= nil then
					Client.RichTextPanel.width = original_width - (lh * 2.75);
					Client.RichTextPanel.text = text;
					Client.RichTextPanel:paginate();
					for i,v in ipairs(Client.RichTextPanel.lines) do
						table.insert(extraText, v);
					end
					extraLines = extraLines + #Client.RichTextPanel.lines;
				end
				
				self:drawRect(0, original_height, width, lh*(extraLines+0.4), self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b);
				if (width) > original_width then
					self:drawRect(original_width, 0, width-original_width, original_height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b);
					self.tooltip:setWidth(width);
				end
				self:drawRectBorder(0, 0, width, original_height + (lh*(extraLines+0.4)), self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b);
				self.tooltip:setHeight(original_height + (lh*(extraLines+0.4)));
				
				local fgBar = {r=0.0, g=0.6, b=0.0, a=0.7}
				local grBar = {r=0.24, g=0.24, b=0.24, a=1}
				local fgText = {r=0.6, g=0.8, b=0.5, a=0.6}
				if itemType == "MandelaArrowShaft" or itemType == "MandelaBowString" or itemType == "MandelaBowString2" then
					self.tooltip:DrawText(self.tooltip:getFont(), getText("Tooltip_weapon_Condition") .. ":", lh*0.4, original_height - (lh*0.4), 1, 1, 0.8, self.borderColor.a);
					Shared.modDataCompatibility(self.item);
					local bar_size = 80;
					if modData.condition ~= nil then bar_size = modData.condition * 80 end
					if bar_size > 80 then bar_size = 80; end
					self:drawRect(lh*7 + 3, original_height + lh*0.4, 80, 3, grBar.a, grBar.r, grBar.g, grBar.b);
					self:drawRect(lh*7 + 3, original_height + lh*0.4, bar_size, 3, fgBar.a, fgBar.r, fgBar.g, fgBar.b);
				elseif itemType == "MandelaBowStave" or itemType == "MandelaBowStave2" then
					self.tooltip:DrawText(self.tooltip:getFont(), getText("UI_MBA_Progress") .. ":", lh*0.4, original_height - (lh*0.4), 1, 1, 0.8, self.borderColor.a);
					local bar_size = 0;
					if modData.progress ~= nil then bar_size = modData.progress * 80 end
					if bar_size > 80 then bar_size = 80; end
					self:drawRect(lh*7 + 3, original_height + lh*0.4, 80, 3, grBar.a, grBar.r, grBar.g, grBar.b);
					self:drawRect(lh*7 + 3, original_height + lh*0.4, bar_size, 3, fgBar.a, fgBar.r, fgBar.g, fgBar.b);
				end
				
				for i,v in ipairs(extraText) do
					self.tooltip:DrawText(self.tooltip:getFont(), v, lh*0.25, original_height + lh*(i-1) - 4, 1, 1, 0.8, self.borderColor.a);
				end
				
				--Adding again after removed.
				if canon then
					self.item:attachWeaponPart(InventoryItemFactory.CreateItem(canon))
				end
				if stock then
					self.item:attachWeaponPart(InventoryItemFactory.CreateItem(stock))
				end
				if recoilpad then
					self.item:attachWeaponPart(InventoryItemFactory.CreateItem(recoilpad))
				end
			end
			--[[if itemType == "MandelaBow"
			or itemType == "MandelaBowUnstrung"
			or itemType == "MandelaBowStave"
			or itemType == "MandelaBowString"
			or itemType == "MandelaArrowWoodDucttapeIron"
			or itemType == "MandelaArrowWoodDucttapeIronTaped"
			or itemType == "MandelaArrowFibreglassColouredTarget"
			or itemType == "MandelaArrowFibreglassColouredIron"
			or itemType == "MandelaArrowBundle"
			or itemType == "MandelaArrowShaft"
			or itemType == "MandelaArrowHeadIron"
			or itemType == "MandelaArrowHeadTarget"
			or itemType == "MandelaFletchings"
			or itemType == "MBAOQuiver"
			or itemType == "MandelaArrowBlank"
			or self.item:getModule() == "MandelaBowAndArrow" then
				local size = math.floor((getTextManager():getFontFromEnum(font_name):getLineHeight() * 1.2857) + 0.5);
				self.tooltip:DrawTextureScaled(Client.logo, self.tooltip:getWidth() - (size + 4), 1, size, size, 1)
			end]] --This is not needed any more, because the game says which mod an item is from in the tooltip.
		end
		ISToolTipInv.prerender = original_prerender;
	end
end

do
--[[
	local original_render = ISContextMenu.render;
	function ISContextMenu:render()
		original_render(self);
		
	end]]--
	--[[
	local original_drawTextureScaledAspect = ISContextMenu.drawTextureScaledAspect;
	function ISContextMenu:drawTextureScaledAspect(texture, x, y, w, h, a, r, g, b)
		original_drawTextureScaledAspect(self, texture, x, y, w, h, a, r, g, b);
	end
	--Client.AttachmentIcons

	local original_drawTexture = ISInventoryPane.drawTexture;
	function ISInventoryPane:drawTexture(texture, x, y, a, r, g, b)
		original_drawTexture(self, texture, x, y, a, r, g, b);
	end
	local original_drawTextureScaledAspect2 = ISInventoryPane.drawTextureScaledAspect;
	function ISInventoryPane:drawTextureScaledAspect(texture, x, y, w, h, a, r, g, b)
		if texture:getName() == Client.arrowBlankTextureName then
			original_drawTextureScaledAspect(self, Client.logo, x, y, w, h, a, r, g, b);
			
		else
			original_drawTextureScaledAspect(self, texture, x, y, w, h, a, r, g, b);
		end
	end]]
end
--[[
function Client.LevelPerk(player, skill, level)
	Client.checkArcherySkill(player)
end]]--

function Client.checkArcherySkill(player)
	--if player:getPerkLevel(Perks.Woodwork) > 0 then
		--ScriptManager.instance:getRecipe("MandelaBowAndArrow.Tape Arrowhead to side of Arrow Shaft"):setNeedToBeLearn(true);
	--end
end

function Client.onNewGame(player, square)
	if player:HasTrait("MBAOarcher") then
		local inventory = player:getInventory();
		--local modData = Shared.getModData(player);
		inventory:AddItem("MandelaBowAndArrow.CompoundBowScorpion");
		--inventory:AddItems("Base.MandelaArrowWoodDucttapeIron",20);
		for i=1, 20 do
			local newArrow = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaArrowBlank");
			local factoryItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaAttachmentShaftWood");
			newArrow:attachWeaponPart(factoryItem);
			factoryItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaAttachmentHeadIron");
			newArrow:attachWeaponPart(factoryItem);
			factoryItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.MandelaAttachmentFletchingsDucttape");
			newArrow:attachWeaponPart(factoryItem);
			Shared.SetArrowName(newArrow);
			player:getInventory():AddItem(newArrow);
		end
		Shared.getModData(player).ReceivedScorpionBow = true;
	end
end

function Client.SetBowAndArrowModel(player, item, number, isServerCommand)
	if Shared.getModData(item).modelVariantNumber ~= number then
		local itemFullType = item:getFullType();
		if Client.Bows[itemFullType] == nil then
			print("bow & arrow mod debug message: Client.SetBowAndArrowModel", item, item:getFullType());
			for i, v in pairs(Client.Bows) do
				print(i, v);
				for i2, v2 in pairs(v) do
					print(" ", i2, v2);
				end
			end
		end
		local modelName = Client.Bows[itemFullType].model;
		if number == 0 then
			item:setWeaponSprite(modelName);
		elseif number == 1 then
			item:setWeaponSprite(modelName .. "Held");
		elseif number == 2 then
			if Shared.getModData(item).modelVariantNumber == 3 then
				number = 3;
			else
				item:setWeaponSprite(modelName .. "Drawn");
			end
		elseif number == 3 then
			item:setWeaponSprite(modelName .. "Held");
		end
		player:resetEquippedHandsModels();
		Shared.getModData(item).modelVariantNumber = number;
		if isClient() and (isServerCommand ~= true) then
			sendClientCommand("MandelaBowAndArrow", "BowModel", {number, player:getPlayerNum()});
		end
	end
end

if isClient() then
	function Client.OnServerCommand(module, command, args)
		if module == "MandelaBowAndArrow" then
			if command == "BowModel" then
				if (args[2] ~= Client.localPlayerObj:getPlayerNum()) then
					local playerObj = getSpecificPlayer(args[2]);
					if playerObj and playerObj:getPrimaryHandItem() then
						Client.SetBowAndArrowModel(playerObj, playerObj:getPrimaryHandItem(), args[1], true);
					end
				end
			end
		end
	end
	Events.OnServerCommand.Add(Client.OnServerCommand);
end

function Client.UnloadArrow(player, item)
	Shared.modDataCompatibility(item);
	if item:getCurrentAmmoCount() > 0 then
		local modData = Shared.getModData(item);
		
		local arrowFullType = "Base.MandelaArrowWoodDucttapeIron";
		local arrowCondition = 10;
		local modDataCopy = {};
		if modData.arrowData ~= nil then
			arrowFullType = modData.arrowData.fullType;
			arrowCondition = modData.arrowData.condition;
			modDataCopy = modData.arrowData.modData;
		else
			print("MBA Error: modData.arrowData is nil")
		end
		local newArrow = InventoryItemFactory.CreateItem(arrowFullType);
		newArrow:setCondition(arrowCondition);
		local arrowModData = newArrow:getModData();
		for i, v in pairs(modDataCopy) do
			arrowModData[v[1]] = v[2];
		end
		if arrowFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
			local attachmentFullType = modData.arrowData.stockFullType;
			local factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
			newArrow:attachWeaponPart(factoryItem);
			if modData.arrowData.canonFullType then
				attachmentFullType = modData.arrowData.canonFullType;
				factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
				newArrow:attachWeaponPart(factoryItem);
			end
			if modData.arrowData.recoilpadFullType then
				attachmentFullType = modData.arrowData.recoilpadFullType;
				factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
				newArrow:attachWeaponPart(factoryItem);
			end
			Shared.SetArrowName(newArrow);
		end
		modData.arrowData = nil;
		player:getInventory():AddItem(newArrow);
		item:setCurrentAmmoCount(item:getCurrentAmmoCount() - item:getAmmoPerShoot());
		if item:getCanon() then
			item:detachWeaponPart(item:getCanon());
		end
		if item:getStock() then
			item:detachWeaponPart(item:getStock());
		end
		if item:getRecoilpad() then
			item:detachWeaponPart(item:getRecoilpad());
		end
		player:resetEquippedHandsModels();
		item:setJammed(false);
	end
end

do
local original_rackBullet = ISRackFirearm.rackBullet;
function ISRackFirearm:rackBullet()
	if Client.isMandelaBow(self.gun:getFullType(),4) then
		Client.UnloadArrow(self.character, self.gun);
	else
		original_rackBullet(self)
	end
end
end

--A custom recipe system so that it can do things differently.
do

local function AddToItemTypeList(arrowList, item, itemFullType)
	if arrowList[itemFullType] == nil then
		arrowList[itemFullType] = {item};
	else
		table.insert(arrowList[itemFullType], item);
	end
end

function Client.CustomRecipesMenu(player, context, items)
	local playerObj = getSpecificPlayer(player);
    local testItem = nil;
	for i,v in ipairs(items) do
		testItem = v;
		if not instanceof(v, "InventoryItem") then
			testItem = v.items[1];
		end
	end
	local testItemFullType = testItem:getFullType();
	if testItemFullType == "MandelaBowAndArrow.MandelaArrowBlank" or Client.ArrowPartData[testItemFullType] ~= nil then
		local arrowShafts = {};
		local arrowsNoHead = {};
		local arrowsNoFletchings = {};
		local arrowsBoth = {};
		
		local arrowsNoHeadBroken = {};
		local arrowsNoFletchingsBroken = {};
		local arrowsBothBroken = {};
		
		local arrowsBrokenWood = {};
		
		local arrowHeads = {};
		local arrowFletchings = {};
		
		local containers = ISInventoryPaneContextMenu.getContainers(playerObj);
		local containersSearched = {};
		for i=1,containers:size() do
			local container = containers:get(i-1);
			local alreadySearched = false;
			for i2,v in ipairs(containersSearched) do
				if v == container then
					alreadySearched = true
					break;
				end
			end
			if not alreadySearched then
				table.insert(containersSearched, container);
				for j=1,container:getItems():size() do
					local item = container:getItems():get(j-1);
					local itemFullType = item:getFullType();
					if itemFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
						if not item:getCanon() then
							if not item:getRecoilpad() then
								if not item:isBroken() then
									table.insert(arrowShafts, item);
								end
							else
								if item:isBroken() then
									table.insert(arrowsNoHeadBroken, item);
								else
									table.insert(arrowsNoHead, item);
								end
							end
						else
							if not item:getRecoilpad() then
								if item:isBroken() then
									table.insert(arrowsNoFletchingsBroken, item);
								else
									table.insert(arrowsNoFletchings, item);
								end
							else
								if item:isBroken() then
									table.insert(arrowsBothBroken, item);
								else
									table.insert(arrowsBoth, item);
								end
							end
						end
						if item:isBroken() and item:getStock():getFullType() == "MandelaBowAndArrow.MandelaAttachmentShaftWood" then
							table.insert(arrowsBrokenWood, item);
						end
					end
					if Client.ArrowPartData[itemFullType] then
						if Client.ArrowPartData[itemFullType].sort == "Head" then
							AddToItemTypeList(arrowHeads, item, itemFullType)
						elseif Client.ArrowPartData[itemFullType].sort == "Fletchings" then
							AddToItemTypeList(arrowFletchings, item, itemFullType)
						end
					end
				end
			end
		end
		if testItemFullType == "MandelaBowAndArrow.MandelaArrowBlank" then
			if not testItem:getCanon() then 
				if not testItem:isBroken() then
					for i,v in pairs(arrowHeads) do
						if testItem:getRecoilpad() then
							Client.AddRecipe(context, Client.Recipes.AddArrowHead, playerObj, testItem, getText("ContextMenu_MBA_Put_On_Arrow", v[1]:getName(), testItem:getName() ), arrowsNoHead, v)
						else
							Client.AddRecipe(context, Client.Recipes.AddArrowHead, playerObj, testItem, getText("ContextMenu_MBA_Put_On_Arrow", v[1]:getName(), testItem:getName() ), arrowShafts, v)
						end
					end
				end
			else
				if testItem:isBroken() then
					if testItem:getRecoilpad() then
						Client.AddRecipe(context, Client.Recipes.RemoveArrowHead, playerObj, testItem, getText("ContextMenu_MBA_Remove_Arrowhead"), arrowsBothBroken, nil)
					else
						Client.AddRecipe(context, Client.Recipes.RemoveArrowHead, playerObj, testItem, getText("ContextMenu_MBA_Remove_Arrowhead"), arrowsNoFletchingsBroken, nil)
					end
				else
					if testItem:getRecoilpad() then
						Client.AddRecipe(context, Client.Recipes.RemoveArrowHead, playerObj, testItem, getText("ContextMenu_MBA_Remove_Arrowhead"), arrowsBoth, nil)
					else
						Client.AddRecipe(context, Client.Recipes.RemoveArrowHead, playerObj, testItem, getText("ContextMenu_MBA_Remove_Arrowhead"), arrowsNoFletchings, nil)
					end
				end
			end
			if not testItem:getRecoilpad() then
				if not testItem:isBroken() then
					for i,v in pairs(arrowFletchings) do
						if testItem:getCanon() then
							Client.AddRecipe(context, Client.Recipes.AddFletchings, playerObj, testItem, getText("ContextMenu_MBA_Put_On_Arrow", v[1]:getName(), testItem:getName() ), arrowsNoFletchings, v)
						else
							Client.AddRecipe(context, Client.Recipes.AddFletchings, playerObj, testItem, getText("ContextMenu_MBA_Put_On_Arrow", v[1]:getName(), testItem:getName()), arrowShafts, v)
						end
					end
				end
			else
				if testItem:isBroken() then
					if testItem:getCanon() then
						Client.AddRecipe(context, Client.Recipes.RemoveFletchings, playerObj, testItem, getText("ContextMenu_MBA_Remove_Fletchings"), arrowsBothBroken, nil)
					else
						Client.AddRecipe(context, Client.Recipes.RemoveFletchings, playerObj, testItem, getText("ContextMenu_MBA_Remove_Fletchings"), arrowsNoHeadBroken, nil)
					end
				else
					if testItem:getCanon() then
						Client.AddRecipe(context, Client.Recipes.RemoveFletchings, playerObj, testItem, getText("ContextMenu_MBA_Remove_Fletchings"), arrowsBoth, nil)
					else
						Client.AddRecipe(context, Client.Recipes.RemoveFletchings, playerObj, testItem, getText("ContextMenu_MBA_Remove_Fletchings"), arrowsNoHead, nil)
					end
				end
			end
			if testItem:isBroken() and testItem:getStock():getFullType() == "MandelaBowAndArrow.MandelaAttachmentShaftWood" then
				Client.AddRecipe(context, Client.Recipes.SnapIntoTwigs, playerObj, testItem, getText("ContextMenu_MBA_snap_into_twigs"), arrowsBrokenWood, nil)
			end
		end
		--playerObj:getPerkLevel(Perks.Woodwork)
	end
end

end

function Client.AddRecipe(context, recipe, playerObj, selectedItem, text, arrows, arrowParts)
	--context:addOption(getText("ContextMenu_MBA_Put_On_Arrow", v[1]:getName(), testItem:getName() ), testItem, Client.OnDoRecipe, playerObj, Client.Recipes.AddArrowHead, arrowsNoHead, arrowHeads);
	local numberOfTimes = #arrows;
	if arrowParts then
		numberOfTimes = math.min(numberOfTimes, #arrowParts);
	end
	--local resultItem = InventoryItemFactory.CreateItem(recipe:getResult():getFullType());
	local option = nil;
	local subMenuCraft = nil;
	if numberOfTimes ~= 1 then
		subMenuCraft = context:getNew(context);
		option = context:addOption(text, selectedItem, nil);
		context:addSubMenu(option, subMenuCraft);
		if playerObj:isDriving() then
			option.notAvailable = true;
		else
			local subOption = subMenuCraft:addOption(getText("ContextMenu_One"), selectedItem, Client.OnDoRecipe, recipe, playerObj, false, arrows, arrowParts);
			--local tooltip = ISRecipeTooltip.addToolTip();
			--tooltip.character = playerObj
			--tooltip.recipe = recipe
			-- add it to our current option
			--tooltip:setName(recipe.name);
			--if resultItem:getTexture() and resultItem:getTexture():getName() ~= "Question_On" then
			--	tooltip:setTexture(resultItem:getTexture():getName());
			--end
			--subOption.toolTip = tooltip;
		
			if numberOfTimes > 1 then
				subOption = subMenuCraft:addOption(getText("ContextMenu_AllWithCount", numberOfTimes), selectedItem, Client.OnDoRecipe, recipe, playerObj, true, arrows, arrowParts);
			else
				subOption = subMenuCraft:addOption(getText("ContextMenu_All"), selectedItem, Client.OnDoRecipe, recipe, playerObj, true, arrows, arrowParts);
			end
			--subOption.toolTip = tooltip;
		end
	else
		option = context:addOption(text, selectedItem, Client.OnDoRecipe, recipe, playerObj, false, arrows, arrowParts);
		--local tooltip = ISInventoryPaneContextMenu.addToolTip();
		--tooltip.description = getText("Tooltip_CantCraftSecondLitCandle");
		--option.toolTip = tooltip;
	end
end

Client.OnDoRecipe = function(selectedItem, recipe, playerObj, all, arrows, arrowParts)
	local containers = ISInventoryPaneContextMenu.getContainers(playerObj);
	for i,v in pairs(arrows) do
		if v:getContainer() ~= playerObj:getInventory() then
			ISTimedActionQueue.add(ISInventoryTransferAction:new(playerObj, v, v:getContainer(), playerObj:getInventory(), nil))
		end
	end
	if arrowParts then
		for i,v in pairs(arrowParts) do
			if v:getContainer() ~= playerObj:getInventory() then
				ISTimedActionQueue.add(ISInventoryTransferAction:new(playerObj, v, v:getContainer(), playerObj:getInventory(), nil))
			end
		end
	end
	for i,v in pairs(arrows) do
		if v == selectedItem then
			table.remove(arrows, i);
			table.insert(arrows, 1, selectedItem);
			break;
		end
	end
	if arrowParts then
		for i,v in pairs(arrowParts) do
			if v == selectedItem then
				table.remove(arrowParts, i);
				table.insert(arrowParts, 1, selectedItem);
				break;
			end
		end
	end
	local action = MBACraftAction:new(playerObj, selectedItem, recipe.time, recipe, playerObj:getInventory());
	for i,v in pairs(arrows) do
		table.insert(action.arrows, v)
	end
	if arrowParts then
		for i,v in pairs(arrowParts) do
			table.insert(action.arrowParts, v)
		end
	end
	if all then
		action:setOnComplete(Client.OnRecipeComplete, action, recipe, playerObj, container, (arrowParts ~= nil))
	end
	ISTimedActionQueue.add(action);
end

Client.OnRecipeComplete = function(completedAction, recipe, playerObj, container, hasArrowparts)--, containers)
	local previousAction = completedAction;
	if hasArrowparts then
		if math.min(#previousAction.arrows, #previousAction.arrowParts) < 1 then return end
	else
		if #previousAction.arrows < 1 then return end
	end
	--local selectedItem = table.remove(previousAction.arrows, 1);
	local selectedItem = previousAction.arrows[1];
	local action = MBACraftAction:new(playerObj, selectedItem, recipe.time, recipe, playerObj:getInventory());
	action.arrows = previousAction.arrows;
	action.arrowParts = previousAction.arrowParts;
	--local arrowParts = {}
	action:setOnComplete(Client.OnRecipeComplete, action, recipe, playerObj, container, hasArrowparts)--, containers, previousAction.arrows, previousAction.arrowParts);
    ISTimedActionQueue.addAfter(previousAction, action);
end
--[[
do
local original_ISInventoryTransferAction_perform = ISInventoryTransferAction.perform;
function ISInventoryTransferAction:perform()
	original_ISInventoryTransferAction_perform();
	if self.item:getFullType() == "MandelaBowAndArrow.MandelaArrowBlank" then
		if self.item:getContainer() == self.character:getInventory() then
			self.item:setWeaponSprite("MandelaBowAndArrow.MandelaArrowBlank");
		else
			if self.item:getCanon() and self.item:getCanon():getFullType() == "MandelaBowAndArrow.MandelaAttachmentHeadIronTaped" then
				self.item:setWeaponSprite("MandelaBowAndArrow.MandelaArrowWoodDucttapeIronTaped");
			else
				if self.item:getRecoilpad() then
					if self.item:getCanon() then
						self.item:setWeaponSprite("MandelaBowAndArrow.MandelaArrowWoodDucttapeIron");
					else
						self.item:setWeaponSprite("MandelaBowAndArrow.MandelaArrowUnheaded");
					end
				else
					if self.item:getCanon() then
						self.item:setWeaponSprite("MandelaBowAndArrow.MandelaArrowUnfletched");
					else
						self.item:setWeaponSprite("MandelaBowAndArrow.MandelaArrowShaftWood");
					end
				end
			end
		end
	end
end
end]]--

Client.RichTextPanel = ISRichTextPanel:new(0, 16, 375, 455);
Client.RichTextPanel:initialise();
Client.RichTextPanel.autosetheight = false;
Client.RichTextPanel:ignoreHeightChange();

function Client.OnCreatePlayer(playerIndex, player)
	local weapon = player:getPrimaryHandItem();
	if weapon ~= nil then
		if Client.isMandelaBow(weapon:getFullType()) then
			Shared.getModData(weapon).modelVariantNumber = nil;
			Client.setUpBow(player, weapon);
			--[[
			if Shared.getModData(weapon).arrowData then
				if Shared.getModData(weapon).arrowData.fullType == "MandelaBowAndArrow.MandelaArrowBlank" then
					if Shared.getModData(weapon).arrowData.stockFullType and (not weapon:getStock()) then
						local attachmentFullType = Shared.getModData(weapon).arrowData.stockFullType;
						local factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
						weapon:attachWeaponPart(factoryItem);
						if Shared.getModData(weapon).arrowData.canonFullType and (not weapon:getCanon()) then
							attachmentFullType = Shared.getModData(weapon).arrowData.canonFullType;
							factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
							weapon:attachWeaponPart(factoryItem);
						end
						if Shared.getModData(weapon).arrowData.recoilpadFullType and (not weapon:getRecoilpad()) then
							attachmentFullType = Shared.getModData(weapon).arrowData.recoilpadFullType;
							factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
							weapon:attachWeaponPart(factoryItem);
						end
					end
				else
					if not weapon:getCanon() then
						local attachmentFullType = Shared.getModData(weapon).arrowData.fullType .. "Attachment";
						local factoryItem = InventoryItemFactory.CreateItem(attachmentFullType);
						weapon:attachWeaponPart(factoryItem);
					end
				end
			end]]
		end
	end
	if player:HasTrait("MBAOarcher") and (not Shared.getModData(player).ReceivedScorpionBow) then
		local inventory = player:getInventory();
		inventory:AddItem("MandelaBowAndArrow.CompoundBowScorpion");
		Shared.getModData(player).ReceivedScorpionBow = true;
	end
end

Events.OnCreatePlayer.Add(Client.OnCreatePlayer);
Events.OnNewGame.Add(Client.onNewGame);
--Events.LevelPerk.Add(Client.LevelPerk);
Events.OnFillInventoryObjectContextMenu.Add(Client.OnFillMenu);
Events.OnZombieDead.Add(Client.OnZombieDead);
--Events.OnLoad.Add(Client.OnLoad);
Events.OnPlayerUpdate.Add(Client.onPlayerUpdate);
Events.OnEquipPrimary.Add(Client.OnEquipPrimary);
Events.OnEquipSecondary.Add(Client.OnEquipSecondary);
Events.OnCreateSurvivor.Add(Client.OnCreateSurvivor);
Events.OnGameBoot.Add(Client.OnGameBoot);