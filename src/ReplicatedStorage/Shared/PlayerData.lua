--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local CropDefinitions = require(Shared:WaitForChild("CropDefinitions"))
local QuestDefinitions = require(Shared:WaitForChild("QuestDefinitions"))

local PlayerData = {}

export type FarmPlot = {
	CropId: string,
	PlantedAt: number,
}

export type QuestProgress = {
	Objectives: { [string]: number },
}

export type Data = {
	SchemaVersion: number,
	Level: number,
	Experience: number,
	Coins: number,
	Inventory: { [string]: number },
	FarmPlots: { [string]: FarmPlot },
	ActiveQuests: { [string]: QuestProgress },
	CompletedQuests: { [string]: boolean },
}

local DATA_FIELDS = {
	SchemaVersion = true,
	Level = true,
	Experience = true,
	Coins = true,
	Inventory = true,
	FarmPlots = true,
	ActiveQuests = true,
	CompletedQuests = true,
}
local LEGACY_FIELDS = {
	Level = true,
	Experience = true,
	Coins = true,
}

local function hasOnlyFields(value: { [string]: unknown }, allowedFields: { [string]: boolean }): boolean
	for key in value do
		if typeof(key) ~= "string" or not allowedFields[key] then
			return false
		end
	end

	return true
end

local function isIntegerInRange(value: unknown, minimum: number, maximum: number): boolean
	if typeof(value) ~= "number" then
		return false
	end

	return value == value
		and value > -math.huge
		and value < math.huge
		and value % 1 == 0
		and value >= minimum
		and value <= maximum
end

local function isValidProgressionValues(levelValue: unknown, experienceValue: unknown): boolean
	return isIntegerInRange(levelValue, 1, GameConfig.Player.MaxLevel)
		and isIntegerInRange(experienceValue, 0, GameConfig.Player.MaxExperience)
end

local function isValidId(value: unknown, maximumLength: number): boolean
	return typeof(value) == "string"
		and #value > 0
		and #value <= maximumLength
		and string.match(value, "^[%w_%-]+$") ~= nil
end

local function validateInventory(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local inventory = value :: { [string]: unknown }
	local itemCount = 0
	for itemId, quantity in inventory do
		local definition = if typeof(itemId) == "string" then ItemDefinitions.Get(itemId) else nil
		if not isValidId(itemId, GameConfig.Inventory.MaxItemIdLength)
			or not definition
			or not isIntegerInRange(quantity, 1, GameConfig.Inventory.MaxQuantityPerItem)
			or (definition ~= nil and typeof(quantity) == "number" and quantity > definition.StackLimit)
		then
			return false
		end
		itemCount += 1
	end

	return itemCount <= GameConfig.Inventory.MaxStoredItemIds
end

local function validateFarmPlots(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local farmPlots = value :: { [string]: unknown }
	local plotCount = 0
	for plotId, rawPlot in farmPlots do
		if not isValidId(plotId, GameConfig.Farming.MaxPlotIdLength) or typeof(rawPlot) ~= "table" then
			return false
		end

		local plot = rawPlot :: { [string]: unknown }
		local cropId = plot.CropId
		if typeof(cropId) ~= "string" then
			return false
		end

		if not hasOnlyFields(plot, { CropId = true, PlantedAt = true })
			or not isValidId(cropId, GameConfig.Inventory.MaxItemIdLength)
			or not CropDefinitions.Get(cropId)
			or not isIntegerInRange(plot.PlantedAt, 0, 9007199254740991)
		then
			return false
		end
		plotCount += 1
	end

	return plotCount <= GameConfig.Farming.MaxStoredPlots
end

local function validateActiveQuests(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local activeQuests = value :: { [string]: unknown }
	local questCount = 0
	for questId, rawProgress in activeQuests do
		local definition = if typeof(questId) == "string" then QuestDefinitions.Get(questId) else nil
		if not isValidId(questId, GameConfig.Inventory.MaxItemIdLength)
			or not definition
			or typeof(rawProgress) ~= "table"
		then
			return false
		end

		local progress = rawProgress :: { [string]: unknown }
		if not hasOnlyFields(progress, { Objectives = true }) or typeof(progress.Objectives) ~= "table" then
			return false
		end

		local objectives = progress.Objectives :: { [string]: unknown }
		local objectiveCount = 0
		for objectiveId, amount in objectives do
			local requiredAmount: number? = nil
			for _, objective in definition.Objectives do
				if objective.Id == objectiveId then
					requiredAmount = objective.RequiredAmount
					break
				end
			end
			if not isValidId(objectiveId, GameConfig.Inventory.MaxItemIdLength)
				or not isIntegerInRange(amount, 0, GameConfig.Player.MaxExperience)
				or requiredAmount == nil
				or (requiredAmount ~= nil and typeof(amount) == "number" and amount > requiredAmount)
			then
				return false
			end
			objectiveCount += 1
		end

		if objectiveCount ~= #definition.Objectives
			or objectiveCount > GameConfig.Quests.MaxObjectivesPerQuest
		then
			return false
		end
		questCount += 1
	end

	return questCount <= GameConfig.Quests.MaxActiveQuests
end

local function validateCompletedQuests(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local completedQuests = value :: { [string]: unknown }
	local questCount = 0
	for questId, completed in completedQuests do
		if not isValidId(questId, GameConfig.Inventory.MaxItemIdLength)
			or not QuestDefinitions.Get(questId)
			or completed ~= true
		then
			return false
		end
		questCount += 1
	end

	return questCount <= GameConfig.Quests.MaxCompletedQuests
end

function PlayerData.GetDefaultData(): Data
	return {
		SchemaVersion = GameConfig.SchemaVersion,
		Level = GameConfig.Player.InitialLevel,
		Experience = GameConfig.Player.InitialExperience,
		Coins = GameConfig.Player.InitialCoins,
		Inventory = {},
		FarmPlots = {},
		ActiveQuests = {},
		CompletedQuests = {},
	}
end

function PlayerData.ValidateData(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local data = value :: { [string]: unknown }
	return hasOnlyFields(data, DATA_FIELDS)
		and data.SchemaVersion == GameConfig.SchemaVersion
		and isValidProgressionValues(data.Level, data.Experience)
		and isIntegerInRange(data.Coins, 0, GameConfig.Player.MaxCoins)
		and validateInventory(data.Inventory)
		and validateFarmPlots(data.FarmPlots)
		and validateActiveQuests(data.ActiveQuests)
		and validateCompletedQuests(data.CompletedQuests)
end

function PlayerData.CloneData(data: Data): Data
	local inventory: { [string]: number } = {}
	for itemId, quantity in data.Inventory do
		inventory[itemId] = quantity
	end

	local farmPlots: { [string]: FarmPlot } = {}
	for plotId, plot in data.FarmPlots do
		farmPlots[plotId] = {
			CropId = plot.CropId,
			PlantedAt = plot.PlantedAt,
		}
	end

	local activeQuests: { [string]: QuestProgress } = {}
	for questId, progress in data.ActiveQuests do
		local objectives: { [string]: number } = {}
		for objectiveId, amount in progress.Objectives do
			objectives[objectiveId] = amount
		end
		activeQuests[questId] = { Objectives = objectives }
	end

	local completedQuests: { [string]: boolean } = {}
	for questId, completed in data.CompletedQuests do
		completedQuests[questId] = completed
	end

	return {
		SchemaVersion = data.SchemaVersion,
		Level = data.Level,
		Experience = data.Experience,
		Coins = data.Coins,
		Inventory = inventory,
		FarmPlots = farmPlots,
		ActiveQuests = activeQuests,
		CompletedQuests = completedQuests,
	}
end

function PlayerData.DataEquals(first: Data, second: Data): boolean
	local function valuesEqual(firstValue: unknown, secondValue: unknown): boolean
		if typeof(firstValue) ~= typeof(secondValue) then
			return false
		end

		if typeof(firstValue) ~= "table" then
			return firstValue == secondValue
		end

		local firstTable = firstValue :: { [string]: unknown }
		local secondTable = secondValue :: { [string]: unknown }
		for key, firstChild in firstTable do
			if not valuesEqual(firstChild, secondTable[key]) then
				return false
			end
		end
		for key in secondTable do
			if firstTable[key] == nil then
				return false
			end
		end
		return true
	end

	return valuesEqual(first, second)
end

function PlayerData.DecodeStoredData(value: unknown): (Data?, string?)
	if typeof(value) ~= "table" then
		return nil, "Los datos guardados no son una tabla."
	end

	local storedData = value :: { [string]: unknown }
	if storedData.SchemaVersion == nil then
		if not hasOnlyFields(storedData, LEGACY_FIELDS)
			or not isValidProgressionValues(storedData.Level, storedData.Experience)
			or not isIntegerInRange(storedData.Coins, 0, GameConfig.Player.MaxCoins)
		then
			return nil, "El registro legado contiene campos desconocidos o valores inválidos."
		end

		local migratedData = PlayerData.GetDefaultData()
		migratedData.Level = storedData.Level :: number
		migratedData.Experience = storedData.Experience :: number
		migratedData.Coins = storedData.Coins :: number
		return migratedData, nil
	end

	if storedData.SchemaVersion ~= GameConfig.SchemaVersion then
		return nil, "La versión del esquema guardado no es compatible."
	end

	if not PlayerData.ValidateData(storedData) then
		return nil, "Los datos guardados no cumplen el esquema actual."
	end

	return PlayerData.CloneData(storedData :: Data), nil
end

return PlayerData
