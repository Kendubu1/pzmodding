local Shared = MandelaBowAndArrow.Shared;
if (MSEAimingSystem == nil) and (Shared.versionNumber == nil or Shared.versionNumber >= 41.54 or Shared.versionNumber <= 40) then
local math = math;
local Client = MandelaBowAndArrow.Client;
Client.MSEAimingSystem = {};
local MSEAimingSystem = Client.MSEAimingSystem;

function MSEAimingSystem.OnCreatePlayer(playerIndex, player)
	local modData = Shared.getModData(player);
	if modData.TargetableZombieList ~= nil then
		local cell = getWorld():getCell();
		for i,v in ipairs(modData.TargetableZombieList) do
			local targetX = v[6];
			local targetY = v[7];
			local targetZ = v[8];
			
			local indicatorSquare = cell:getGridSquare(targetX,targetY,targetZ);
			local items = indicatorSquare:getWorldObjects();
			for i=items:size() - 1, 0, -1 do
				if items:get(i):getItem():getFullType() == "MandelaBowAndArrow.AimingIndicatorGreen"
				or items:get(i):getItem():getFullType() == "MandelaBowAndArrow.AimingIndicatorGrey" then
					items:get(i):removeFromSquare();
				end
			end
		end
	end
end

function MSEAimingSystem.updateTargetFinding(player)
	if player:isAiming() and player:getPrimaryHandItem() ~= nil and Client.Bows[player:getPrimaryHandItem():getFullType()] ~= nil then
		local weapon = player:getPrimaryHandItem();
		local modData = Shared.getModData(player);
		
		local playerX = player:getX()
		local playerY = player:getY()
		local playerZ = player:getZ()
		local mouseX, mouseY = ISCoordConversion.ToWorld(getMouseXScaled(), getMouseYScaled(), 0);
		local targetMouseX = mouseX+1.5;
		local targetMouseY = mouseY+1.5;
		local direction = (math.atan2(targetMouseY-playerY, targetMouseX-playerX));
		
		local feetDirection = player:getDir():toAngle();
		if feetDirection < 2 then
			feetDirection = -(feetDirection+(math.pi*0.5))
		else
			feetDirection = (math.pi*2)-(feetDirection+(math.pi*0.5))
		end
		--if math.cos(direction - feetDirection) < math.cos(67.5) then
		if math.cos(direction - feetDirection) < math.cos(0.78) then
			if math.sin(direction - feetDirection) < 0 then
				direction = feetDirection - (math.pi*0.25)
			else
				direction = feetDirection + (math.pi*0.25)
			end
		end --Avoids an aiming angle pointing behind the person
		
		local aimingAngle = Client.Bows[weapon:getFullType()].aimingAngle;
		local aimingDistance = Client.Bows[weapon:getFullType()].aimingDistance;
		
		if weapon:getRecoilpad() and weapon:getRecoilpad():getFullType() == "MandelaBowAndArrow.MandelaAttachmentFletchingsDucttapeFluFlu" then
			aimingDistance = 8
		end
		
		local playerOffsetX = playerX - math.floor(playerX);
		local playerOffsetY = playerY - math.floor(playerY);
		
		local mWorldZ = playerZ;
		
		playerZ = player:getZ();
		
		local cell = getWorld():getCell();
		local square = cell:getGridSquare(math.floor(targetMouseX), math.floor(targetMouseY), playerZ);
		if playerZ > 0 then
			for i=math.floor(playerZ), 1, -1 do
				square = cell:getGridSquare(math.floor(mouseX+1.5)+(i*3), math.floor(mouseY+1.5)+(i*3), i);
				if square and square:isSolidFloor() then
					targetMouseX = mouseX+1.5+i;
					targetMouseY = mouseY+1.5+i;
					break
				end
			end
		end
		
		local direction2 = direction;
		if direction2 < 0 then direction2 = -direction2 end
		if direction2 > (math.pi/2) then direction2 = direction2 - (math.pi/2) end
		if direction2 > (math.pi/4) then direction2 = (math.pi/2) - direction2 end
		
		local hypotenuse = 1/math.cos(direction2)
		local hypotenuse2 = hypotenuse;
		
		MSEAimingSystem.BlockedAngleList = {};
		MSEAimingSystem.TargetableZombieList = {};
		local ContinuingDistance = true;
		local i = 1
		while ContinuingDistance do
			hypotenuse2 = hypotenuse2 + hypotenuse;
			if (hypotenuse2*hypotenuse) >= (aimingDistance + (hypotenuse2/2)) then
				ContinuingDistance = false
			else
				MSEAimingSystem.CheckingCellList = {};
				MSEAimingSystem.CheckingZombieList = {};
				local frontX = math.floor((math.cos((direction))*(hypotenuse*i))+0.001);
				local frontY = math.floor((math.sin((direction))*(hypotenuse*i))+0.001);
				local FrontSquare = cell:getGridSquare(playerX+frontX, playerY+frontY, playerZ);
				MSEAimingSystem.CheckingCellList[#MSEAimingSystem.CheckingCellList+1] = FrontSquare;
				MSEAimingSystem.ContinueRight(cell,playerX,playerY,playerZ,playerOffsetX,playerOffsetY,frontX,frontY,FrontSquare,direction,math.rad(aimingAngle),hypotenuse,hypotenuse2);
				MSEAimingSystem.ContinueLeft(cell,playerX,playerY,playerZ,playerOffsetX,playerOffsetY,frontX,frontY,FrontSquare,direction,math.rad(aimingAngle),hypotenuse,hypotenuse2);
				for i,v in ipairs(MSEAimingSystem.CheckingCellList) do
					MSEAimingSystem.CheckSquareForZombies(v,playerX,playerY)
				end
				
				table.sort(MSEAimingSystem.CheckingZombieList, function(a,b)
					local aNum = a[2];
					local bNum = b[2];
					return aNum < bNum;
				end)
				
				for _, subTable in ipairs(MSEAimingSystem.CheckingZombieList) do
					if player:CanSee(subTable[1]) and subTable[2] <= aimingDistance then
						MSEAimingSystem.TryAddingTarget(subTable[1],subTable[2],playerX,playerY,aimingAngle,targetMouseX,targetMouseY)
					end
				end
				
				if (i * hypotenuse) > aimingDistance then
					ContinuingDistance = false;
				end
			end
			i = i + 1;
		end

		table.sort(MSEAimingSystem.TargetableZombieList, function(a,b)
			local aNum = a[4];
			local bNum = b[4];
			return aNum < bNum;
		end)
		
		local shortestDistanceMouse = 1;
		local closestTargetMouse = nil;
		local primaryTargetNumber = 1;
		for _, subTable in ipairs(MSEAimingSystem.TargetableZombieList) do
			if subTable[5] < shortestDistanceMouse then
				closestTargetMouse = subTable[1];
				shortestDistanceMouse = subTable[5];
				primaryTargetNumber = _;
			end
		end
		
		local primaryTarget = nil;
		if closestTargetMouse ~= nil then
			primaryTarget = closestTargetMouse;
		elseif MSEAimingSystem.TargetableZombieList[1] ~= nil then
			primaryTarget = MSEAimingSystem.TargetableZombieList[1][1];
		end
		if primaryTarget ~= nil then
			local targetLastX, targetLastY = modData.targetLastX, modData.targetLastY;
			modData.lastTimeMultiplier = getGameTime():getMultiplier();
			local targetX = MSEAimingSystem.TargetableZombieList[primaryTargetNumber][6];
			local targetY = MSEAimingSystem.TargetableZombieList[primaryTargetNumber][7];
			local targetZ = MSEAimingSystem.TargetableZombieList[primaryTargetNumber][8];
			modData.targetLastX, modData.targetLastY = targetX, targetY;
			modData.targetXSpeed = (targetX - (targetLastX or targetX)) / modData.lastTimeMultiplier;
			modData.targetYSpeed = (targetY - (targetLastY or targetY)) / modData.lastTimeMultiplier;
			if not MSEAimingSystem.TargetIndicatorGreen then
				local items = player:getInventory();
				MSEAimingSystem.TargetIndicatorGreen = items:getItemFromType("AimingIndicatorGreen");
				if not MSEAimingSystem.TargetIndicatorGreen then
					local newItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.AimingIndicatorGreen");
					items:AddItem(newItem);
					newItem:setFavorite(true);
					MSEAimingSystem.TargetIndicatorGreen = newItem
				end
			end
			if not MSEAimingSystem.TargetIndicatorGrey then
				local items = player:getInventory();
				MSEAimingSystem.TargetIndicatorGrey = items:getItemFromType("AimingIndicatorGrey");
				if not MSEAimingSystem.TargetIndicatorGrey then
					local newItem = InventoryItemFactory.CreateItem("MandelaBowAndArrow.AimingIndicatorGrey");
					items:AddItem(newItem);
					newItem:setFavorite(true);
					MSEAimingSystem.TargetIndicatorGrey = newItem
				end
			end
			local playerNum = player:getPlayerNum();
		end
		MSEAimingSystem.primaryTarget = primaryTarget;
		modData.primaryTarget = primaryTarget;
	elseif Client.MSEAimingSystem.primaryTarget then
		Client.MSEAimingSystem.primaryTarget = nil;
		Shared.getModData(player).primaryTarget = nil;
	end
	Shared.getModData(player).TargetableZombieList = MSEAimingSystem.TargetableZombieList;
end

function MSEAimingSystem.TryAddingTarget(target,distance,playerX,playerY,aimingAngle,targetMouseX,targetMouseY)
	local targetX = target:getX();
	local targetY = target:getY();
	local targetZ = target:getZ();
	local zombieSpan = (math.pi/9) / distance;
	local direction = math.atan2(targetX-playerX, targetY-playerY);
	local blocked = false;
	for i, v in ipairs(MSEAimingSystem.BlockedAngleList) do
		local difference1 = direction - v[1];
		while (difference1 < -math.pi) do difference1 = difference1 + (math.pi*2); end
		while (difference1 > math.pi) do difference1 = difference1 - (math.pi*2); end
		local difference2 = direction - v[2];
		while (difference2 < -math.pi) do difference2 = difference2 + (math.pi*2); end
		while (difference2 > math.pi) do difference2 = difference2 - (math.pi*2); end
		if difference1 > 0 and difference2 < 0 then
			blocked = true;
			break
		end
	end
	if not blocked then
		table.insert(MSEAimingSystem.BlockedAngleList, {direction-zombieSpan, direction+zombieSpan});
		local priority = distance * (1 + (direction / aimingAngle));
		local distanceFromCursor = math.sqrt(((targetX-targetMouseX)^2)+((targetY-targetMouseY)^2));
		table.insert(MSEAimingSystem.TargetableZombieList, {target, direction, distance, priority, distanceFromCursor, targetX, targetY, targetZ});
	end
end

function MSEAimingSystem.CheckSquareForZombies(square,playerX,playerY)
	local movingObjects = square:getMovingObjects();
	local slayZombie = nil;
	if (movingObjects ~= nil) then
		for ii=0, movingObjects:size()-1 do
			if string.find(tostring(movingObjects:get(ii)),"IsoFallingClothing") == nil then
				if( movingObjects:get(ii):isZombie() ) then
					local target = movingObjects:get(ii);
					local targetX = target:getX();
					local targetY = target:getY();
					local zombieDistance = math.sqrt(((targetX-playerX)^2)+((targetY-playerY)^2));
					table.insert(MSEAimingSystem.CheckingZombieList, {target, zombieDistance});
				end
			end
		end
	end
end

function MSEAimingSystem.ContinueRight(cell,playerX,playerY,playerZ,playerOffsetX,playerOffsetY,rightX,rightY,FrontSquare,direction,aimingAngle,hypotenuse,hypotenuse2)
	local furthest = rightX;
	if rightY^2 > furthest^2 then furthest = rightY; end
	if furthest < 0 then furthest = -furthest; end
	local continuingSideways = true
	while continuingSideways do
		local direction3 = math.atan2((rightY+0.5)-playerOffsetY, (rightX+0.5)-playerOffsetX);
		if (furthest == rightX) and (rightY ~= furthest) then
			rightY = rightY + 1;
		elseif (furthest == -rightX) and (rightY ~= -furthest) then
			rightY = rightY - 1;
		elseif (furthest == rightY) and (rightX ~= -furthest) then
			rightX = rightX - 1;
		elseif (furthest == -rightY) and (rightX ~= furthest) then
			rightX = rightX + 1;
		end
		local direction2 = math.atan2(rightY+0.5-playerOffsetY, rightX+0.5-playerOffsetX);
		local distance = math.sqrt(((rightX+0.5-playerOffsetX)^2)+((rightY+0.5-playerOffsetY)^2));
		
		local RightSquare = cell:getGridSquare(playerX+rightX+0.001, playerY+rightY+0.001, playerZ);
		
		local difference = direction2-direction;
		--while (difference > (math.pi/2)) do difference = difference - (math.pi) end
		--while (difference < (-math.pi/2)) do difference = difference + (math.pi) end
		if (math.cos(difference) < math.cos((aimingAngle/2) + (((math.pi/4)/distance)*1.42))) then
			continuingSideways = false;
		else
			MSEAimingSystem.CheckingCellList[#MSEAimingSystem.CheckingCellList+1] = RightSquare;
			MSEAimingSystem.ContinueRight(cell,playerX,playerY,playerZ,playerOffsetX,playerOffsetY,rightX,rightY,FrontSquare,direction,aimingAngle,hypotenuse,hypotenuse2);
		end
		continuingSideways = false
	end
end

function MSEAimingSystem.ContinueLeft(cell,playerX,playerY,playerZ,playerOffsetX,playerOffsetY,leftX,leftY,FrontSquare,direction,aimingAngle,hypotenuse,hypotenuse2)
	local furthest = leftX;
	if leftY^2 > furthest^2 then furthest = leftY; end
	if furthest < 0 then furthest = -furthest; end
	local continuingSideways = true
	local directionA = math.atan2((leftY+0.5)-playerOffsetY, (leftX+0.5)-playerOffsetX);
	while continuingSideways do
		local direction3 = math.atan2((leftY+0.5)-playerOffsetY, (leftX+0.5)-playerOffsetX);
		if (furthest == leftX) and (leftY ~= -furthest) then
			leftY = leftY - 1;
		elseif (furthest == -leftX) and (leftY ~= furthest) then
			leftY = leftY + 1;
		elseif (furthest == leftY) and (leftX ~= furthest) then
			leftX = leftX + 1;
		elseif (furthest == -leftY) and (leftX ~= -furthest) then
			leftX = leftX - 1;
		end
		local direction2 = math.atan2(leftY+0.5-playerOffsetY, leftX+0.5-playerOffsetX);
		local distance = math.sqrt(((leftX+0.5-playerOffsetX)^2)+((leftY+0.5-playerOffsetY)^2));
		
		local LeftSquare = cell:getGridSquare(playerX+leftX+0.001, playerY+leftY+0.001, playerZ);
		
		if (math.cos(direction-direction2) < math.cos((aimingAngle/2) + (((math.pi/4)/distance)*1.42))) then
			continuingSideways = false;
		else
			MSEAimingSystem.CheckingCellList[#MSEAimingSystem.CheckingCellList+1] = LeftSquare;
			MSEAimingSystem.ContinueLeft(cell,playerX,playerY,playerZ,playerOffsetX,playerOffsetY,leftX,leftY,FrontSquare,direction,aimingAngle,hypotenuse,hypotenuse2);
		end
		continuingSideways = false
	end
end

function MSEAimingSystem.onPlayerUpdate(player)
	if player:isLocalPlayer() then
		MSEAimingSystem.updateTargetFinding(player);
	end
end

Events.OnPlayerUpdate.Add(MSEAimingSystem.onPlayerUpdate);
Events.OnCreatePlayer.Add(MSEAimingSystem.OnCreatePlayer);
end