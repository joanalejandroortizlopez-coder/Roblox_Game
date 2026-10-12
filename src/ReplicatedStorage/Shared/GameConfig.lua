--!strict

type Config = {
	SchemaVersion: number,
	Player: {
		InitialLevel: number,
		MaxLevel: number,
		InitialExperience: number,
		MaxExperience: number,
		InitialCoins: number,
		MaxCoins: number,
	},
	Progression: {
		BaseExperience: number,
		LinearExperiencePerLevel: number,
		QuadraticExperiencePerLevel: number,
		MaxGrantPerAction: number,
	},
	Inventory: {
		InitialCapacity: number,
		MaxCapacity: number,
		MaxQuantityPerItem: number,
		MaxStoredItemIds: number,
		MaxItemIdLength: number,
	},
	Farming: {
		MaxStoredPlots: number,
		MaxPlotIdLength: number,
	},
	Quests: {
		MaxActiveQuests: number,
		MaxCompletedQuests: number,
		MaxObjectivesPerQuest: number,
		MaxProgressPerAction: number,
	},
}

local GameConfig: Config = {
	SchemaVersion = 2,
	Player = {
		InitialLevel = 1,
		MaxLevel = 10000,
		InitialExperience = 0,
		MaxExperience = 2147483647,
		InitialCoins = 0,
		MaxCoins = 2147483647,
	},
	Progression = {
		BaseExperience = 100,
		LinearExperiencePerLevel = 25,
		QuadraticExperiencePerLevel = 5,
		MaxGrantPerAction = 1000000,
	},
	Inventory = {
		InitialCapacity = 20,
		MaxCapacity = 100,
		MaxQuantityPerItem = 999,
		MaxStoredItemIds = 100,
		MaxItemIdLength = 64,
	},
	Farming = {
		MaxStoredPlots = 100,
		MaxPlotIdLength = 64,
	},
	Quests = {
		MaxActiveQuests = 20,
		MaxCompletedQuests = 500,
		MaxObjectivesPerQuest = 32,
		MaxProgressPerAction = 100000,
	},
}

table.freeze(GameConfig.Player)
table.freeze(GameConfig.Progression)
table.freeze(GameConfig.Inventory)
table.freeze(GameConfig.Farming)
table.freeze(GameConfig.Quests)

return table.freeze(GameConfig)
