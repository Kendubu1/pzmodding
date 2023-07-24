-- script used to refereces we're items should be spawned in pz
-- weapon has high chance to be found in garage or police station
-- mag has low chances to be found in a mailbox & high chance in libray or bookstore

require 'Items/ProceduralDistributions'
require 'Items/Distributions'


table.insert(ProceduralDistributions.list["GarageTools"],"JunkJet.JunkJet_Weapon");
table.insert(ProceduralDistributions.list["GarageTools"],10);
table.insert(ProceduralDistributions.list["GarageTools"],"JunkJet.JunkJet_Mag");
table.insert(ProceduralDistributions.list["GarageTools"],10);

table.insert(ProceduralDistributions["list"]["PoliceStorageGuns"].items, "JunkJet.JunkJet_Weapon");
table.insert(ProceduralDistributions["list"]["PoliceStorageGuns"].items, 10);
table.insert(ProceduralDistributions["list"]["PoliceStorageGuns"].items, "JunkJet.JunkJet_Mag");
table.insert(ProceduralDistributions["list"]["PoliceStorageGuns"].items, 10);

table.insert(ProceduralDistributions["list"]["BookstoreBooks"].items, "JunkJet.JunkJet_Mag");
table.insert(ProceduralDistributions["list"]["BookstoreBooks"].items, 10);
table.insert(ProceduralDistributions["list"]["LibraryBooks"].items, "JunkJet.JunkJet_Mag");
table.insert(ProceduralDistributions["list"]["LibraryBooks"].items, 10);

table.insert(ProceduralDistributions.list["EngineerTools"].items, "JunkJet.JunkJet_Mag");
table.insert(ProceduralDistributions.list["EngineerTools"].items, 3);
table.insert(ProceduralDistributions.list["EngineerTools"].items, "JunkJet.JunkJet_Weapon");
table.insert(ProceduralDistributions.list["EngineerTools"].items, 3);

table.insert(SuburbsDistributions["all"]["postbox"].items, "JunkJet.JunkJet_Mag");
table.insert(SuburbsDistributions["all"]["postbox"].items, 1);