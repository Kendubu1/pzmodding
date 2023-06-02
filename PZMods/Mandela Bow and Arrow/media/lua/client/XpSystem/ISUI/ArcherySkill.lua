--[[
require 'XpSystem/ISUI/extraskills'
local Client = MandelaBowAndArrow.Client
local Shared = MandelaBowAndArrow.Shared

if Shared.versionNumber ~= nil and Shared.versionNumber < 41.51 and Shared.versionNumber > 40 then
	--table.insert(extraskills.PerkCat, "Others"); To add a new category
	--extraskills.PerkList["Others"] = {}; Add new skills to this category in this table
	--extraskills.PerkName["Others"] = "ContextMenu_Others";

	--To add your skill in an existing category change "Misc" for the internal name i.e. "Crafting" or "Survivalist"

	extraskills.PerkList["Combat"] = extraskills.PerkList["Combat"] or {};
	--extraskills.PerkName["Combat"] = "UI_optionscreen_binding_Combat";
	table.insert(extraskills.PerkList["Combat"], "Archery");

	extraskills.skills["Archery"] = {};
	extraskills.skills["Archery"].name = "Archery";--"ContextMenu_Archery";
	extraskills.skills["Archery"].level = 0; --Starting level
	extraskills.skills["Archery"].xp = 0;    --Starting XP
	extraskills.skills["Archery"].boost = 0.25;
	extraskills.skills["Archery"].multiplier = 0; --Standard multiplier for skills

	function Client.StartArcherySkill (player,square)
			local modData = player:getModData();
			if modData.skills ~= nil then
				if player:HasTrait("MBAOarcher") then
					modData.skills["Archery"].boost = 1;
					modData.skills["Archery"].level = 4;
					modData.skills["Archery"].xp = ISModSkillProgressBar.getPreviousXpLvl(nil,4);
				end
			else
				if player:HasTrait("MBAOarcher") then
					extraskills.skills["Archery"].boost = 1;
					extraskills.skills["Archery"].level = 4;
					extraskills.skills["Archery"].xp = ISModSkillProgressBar.getPreviousXpLvl(nil,4);
				end
			end
	end
	Events.OnNewGame.Add(Client.StartArcherySkill);
end

local getXpForLvl = function(level)
	local xp = 75
	if level == 1 then
		xp = 75;
	elseif level == 2 then
		xp = 150;	
	elseif level == 3 then
		xp = 300;
	elseif level == 4 then
		xp = 750;
	elseif level >= 5 then
		xp = 1500 * (level - 3);
	end
	return xp;
end

function Client.LoadArcherySkill()
	local player = getPlayer();	
	local modData = player:getModData();
	if Shared.versionNumber ~= nil and Shared.versionNumber < 41.51 and Shared.versionNumber > 40 then
		if modData.skills == nil then
			modData.skills = extraskills.skills;
		end
		if modData.skills["Archery"] == nil then
			modData.skills["Archery"] = extraskills.skills["Archery"];
		end
	else
		if (Shared.getModData(player).transferredArcherySkill ~= true) and modData.skills and modData.skills["Archery"] then
			for i=1, modData.skills["Archery"].level do
				player:LevelPerk(Perks.Archery);
			end
			local xp = player:getModData().skills["Archery"].xp - getXpForLvl(modData.skills["Archery"].level)
			player:getXp():setXPToLevel(Perks.Archery, modData.skills["Archery"].level)
			player:getXp():AddXP(Perks.Archery, xp);
			Shared.getModData(player).transferredArcherySkill = true;
		end
	end
end

Events.OnLoad.Add(Client.LoadArcherySkill);
]]--