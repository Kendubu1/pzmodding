--This is what renders the green and grey circles over zombies.
local Client = MandelaBowAndArrow.Client;

Client.MBA_UI_ModelShower = ISUIElement:derive("MBA_UI_ModelShower");

function Client.MBA_UI_ModelShower:render()
	if Client.MSEAimingSystem.primaryTarget then
		local targetX = Client.MSEAimingSystem.primaryTarget:getX();
		local targetY = Client.MSEAimingSystem.primaryTarget:getY();
		local targetZ = Client.MSEAimingSystem.primaryTarget:getZ();
		local indicatorSquare = getWorld():getCell():getGridSquare(targetX,targetY,targetZ);
		Render3DItem(Client.MSEAimingSystem.TargetIndicatorGreen, indicatorSquare, targetX, targetY, targetZ, 0);
		for i,v in pairs(Client.MSEAimingSystem.TargetableZombieList) do
			if v[1] ~= Client.MSEAimingSystem.primaryTarget then
				local targetX = v[1]:getX();
				local targetY = v[1]:getY();
				local targetZ = v[1]:getZ();
				local indicatorSquare = getWorld():getCell():getGridSquare(targetX,targetY,targetZ);
				Render3DItem(Client.MSEAimingSystem.TargetIndicatorGrey, indicatorSquare, targetX, targetY, targetZ, 0);
			end
		end
	end
end

local Shared = MandelaBowAndArrow.Shared;
function Client.MBA_UI_ModelShower.launch()
	if (Shared.versionNumber == nil or Shared.versionNumber >= 41.54 or Shared.versionNumber <= 40) then
		local modelShower = Client.MBA_UI_ModelShower:new(0, 0, 1, 1);
		modelShower:initialise();
		modelShower:addToUIManager();
		Client.modelShower = modelShower;
	end
end

Events.OnGameStart.Add(Client.MBA_UI_ModelShower.launch);