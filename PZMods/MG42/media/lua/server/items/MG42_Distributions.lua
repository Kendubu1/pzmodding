Distributions = Distributions or {};

local distributionTable = 
{

	gunstore = {
        counter ={
            rolls = 3,
            items = {
                "MG420.MG42BulletsBox", 1,
                "MG420.MG42", 0.5,
                "MG420.MG42Can", 1,
            },
            dontSpawnAmmo = true,
        },

        displaycase ={
            rolls = 3,
            items = {
                "MG420.MG42BulletsBox", 1,
                "MG420.MG42", 0.5,
                "MG420.MG42Can", 0.5,
            },
            dontSpawnAmmo = true,
        },

        locker ={
            rolls = 3,
            items = {
                "MG420.MG42", 0.3,.5,
                "MG420.MG42Can", 0.5,
            },
            dontSpawnAmmo = true,
        },

        metal_shelves ={
            rolls = 2,
            items = {
                "MG420.MG42", 0.5,
                "MG420.MG42Can", 1,

            },
        },
    },

    gunstorestorage ={
        all={
            rolls = 2,
            items = {
                "MG420.MG42BulletsBox", 2,
                "MG420.MG42", 0.2,
                
            },
        },
    },
	
	armysurplus = {
        shelves = {
            rolls = 2,
            items = {
			"MG420.MG42BulletsBox", 2,
            "MG420.MG42", 0.5,
            "MG420.MG42Can", 0.5,
            },
        },
        
        metal_shelves = {
            rolls = 2,
            items = {
			"MG420.MG42BulletsBox", 2,
            "MG420.MG42", 0.5,
            "MG420.MG42Can", 0.5,  
            },
        },
    },
}

table.insert(Distributions, distributionTable);
