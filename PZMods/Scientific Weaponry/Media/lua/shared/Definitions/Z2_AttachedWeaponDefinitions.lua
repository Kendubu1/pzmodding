require "Definitions/AttachedWeaponDefinitions"

AttachedWeaponDefinitions = AttachedWeaponDefinitions or {};

-- Super Sledgehammers on certain zombie spawns
AttachedWeaponDefinitions.supersledgeholster1 = {
	chance = 2,
	outfit = {"HazardSuit", "ArmyCamoDesert","PrivateMilitia"},
	weaponLocation =  {"Blade On Back"},
	bloodLocations = nil,
	addHoles = false,
	daySurvived = 0,
	weapons = {
		"Base.Sledgehammer4",
	},
}

AttachedWeaponDefinitions.supersledgeholster2 = {
	chance = 1,
	outfit = {"Survivor", "Survivor0", "Survivor1"},
	weaponLocation =  {"Blade On Back"},
	bloodLocations = nil,
	addHoles = false,
	daySurvived = 20,
	weapons = {
		"Base.Sledgehammer5",
	},
}

