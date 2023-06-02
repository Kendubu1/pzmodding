require "Items/SuburbsDistributions"
require "Items/ItemPicker"

CChainSaw = {}
CChainSaw.getSprites = function()
	getTexture("Item_ChainSaw.png");
	print("Textures and Sprites Loaded.");
end

	table.insert(SuburbsDistributions["storageunit"]["all"].items, "ChainSaw.ChainSaw");
	table.insert(SuburbsDistributions["storageunit"]["all"].items, 4);

	-- Avery rare in crates, locker and metal shelves
	table.insert(SuburbsDistributions["all"]["crate"].items, "ChainSaw.ChainSaw");
	table.insert(SuburbsDistributions["all"]["crate"].items, 2);

	table.insert(SuburbsDistributions["all"]["metal_shelves"].items, "ChainSaw.ChainSaw");
	table.insert(SuburbsDistributions["all"]["metal_shelves"].items, 2);
	
	table.insert(SuburbsDistributions["storageunit"]["all"].items, "ChainSaw.ChainSawNoGas");
	table.insert(SuburbsDistributions["storageunit"]["all"].items, 4);

	-- Avery rare in crates, locker and metal shelves
	table.insert(SuburbsDistributions["all"]["crate"].items, "ChainSaw.ChainSawNoGas");
	table.insert(SuburbsDistributions["all"]["crate"].items, 2);

	table.insert(SuburbsDistributions["all"]["metal_shelves"].items, "ChainSaw.ChainSawNoGas");
	table.insert(SuburbsDistributions["all"]["metal_shelves"].items, 4);
	
	table.insert(SuburbsDistributions["toolstore"]["shelves"].items, "ChainSaw.ChainSawNoGas");
	table.insert(SuburbsDistributions["toolstore"]["shelves"].items, 4);
	
	table.insert(SuburbsDistributions["toolstore"]["counter"].items, "ChainSaw.ChainSawNoGas");
	table.insert(SuburbsDistributions["toolstore"]["counter"].items, 4);
	
	


print("ChainSaw: SuburbsDistributions added. ");
Events.OnPreMapLoad.Add(CChainSaw.getSprites);