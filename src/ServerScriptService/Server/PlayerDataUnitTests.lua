--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

type Data = PlayerData.Data

type TestCase = {
	Name: string,
	Run: () -> (),
}

type RunResult = {
	Passed: number,
	Failed: number,
	Failures: { string },
}

local PlayerDataUnitTests = {}
local testCases: { TestCase } = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function addCase(name: string, run: () -> ())
	table.insert(testCases, {
		Name = name,
		Run = run,
	})
end

local function makeValidData(): Data
	local data = PlayerData.GetDefaultData()
	data.Inventory.wheat_seed = 2
	data.FarmPlots.plot_a = {
		CropId = "wheat",
		PlantedAt = 100,
	}
	data.ActiveQuests.gather_fiber = {
		Objectives = {
			collect_fiber = 2,
		},
	}
	data.CompletedQuests.reach_level_2 = true
	return data
end

local function makeRecord(data: Data): { [string]: unknown }
	return {
		SchemaVersion = data.SchemaVersion,
		Level = data.Level,
		Experience = data.Experience,
		Coins = data.Coins,
		Inventory = data.Inventory,
		FarmPlots = data.FarmPlots,
		ActiveQuests = data.ActiveQuests,
		CompletedQuests = data.CompletedQuests,
	}
end

addCase("defaults have the configured schema and are valid", function()
	local data = PlayerData.GetDefaultData()
	expect(PlayerData.ValidateData(data), "GetDefaultData returned data rejected by ValidateData")
	expect(data.SchemaVersion == GameConfig.SchemaVersion, "default schema version differs from GameConfig")
	expect(data.Level == GameConfig.Player.InitialLevel, "default level differs from GameConfig")
	expect(data.Experience == GameConfig.Player.InitialExperience, "default experience differs from GameConfig")
	expect(data.Coins == GameConfig.Player.InitialCoins, "default coins differ from GameConfig")
	expect(next(data.Inventory) == nil, "default inventory is not empty")
	expect(next(data.FarmPlots) == nil, "default farm plots are not empty")
	expect(next(data.ActiveQuests) == nil, "default active quests are not empty")
	expect(next(data.CompletedQuests) == nil, "default completed quests are not empty")
end)

addCase("default calls return independent nested tables", function()
	local first = PlayerData.GetDefaultData()
	local second = PlayerData.GetDefaultData()

	first.Level += 1
	first.Inventory.wheat_seed = 1
	first.FarmPlots.plot_a = { CropId = "wheat", PlantedAt = 100 }
	first.ActiveQuests.gather_fiber = { Objectives = { collect_fiber = 1 } }
	first.CompletedQuests.reach_level_2 = true

	expect(second.Level == GameConfig.Player.InitialLevel, "scalar data was shared")
	expect(second.Inventory.wheat_seed == nil, "inventory table was shared")
	expect(second.FarmPlots.plot_a == nil, "farm plot table was shared")
	expect(second.ActiveQuests.gather_fiber == nil, "active quest table was shared")
	expect(second.CompletedQuests.reach_level_2 == nil, "completed quest table was shared")
end)

addCase("ValidateData accepts a complete valid v2 record", function()
	expect(PlayerData.ValidateData(makeValidData()), "valid v2 fixture was rejected")
end)

addCase("ValidateData rejects missing, mistyped, and extra fields", function()
	expect(not PlayerData.ValidateData({}), "empty record was accepted")

	local wrongType = makeRecord(PlayerData.GetDefaultData())
	wrongType.Coins = "0"
	expect(not PlayerData.ValidateData(wrongType), "string coins were accepted")

	local extraField = makeRecord(PlayerData.GetDefaultData())
	extraField.Unrecognized = true
	expect(not PlayerData.ValidateData(extraField), "unknown field was accepted")
end)

addCase("ValidateData enforces configured numeric bounds and finite values", function()
	local validBounds = PlayerData.GetDefaultData()
	validBounds.Level = GameConfig.Player.MaxLevel
	validBounds.Experience = GameConfig.Player.MaxExperience
	validBounds.Coins = GameConfig.Player.MaxCoins
	expect(PlayerData.ValidateData(validBounds), "configured inclusive maximums were rejected")

	local invalidLevel = makeRecord(PlayerData.GetDefaultData())
	invalidLevel.Level = GameConfig.Player.MaxLevel + 1
	expect(not PlayerData.ValidateData(invalidLevel), "level above maximum was accepted")

	local invalidExperience = makeRecord(PlayerData.GetDefaultData())
	invalidExperience.Experience = -1
	expect(not PlayerData.ValidateData(invalidExperience), "negative experience was accepted")

	local invalidCoins = makeRecord(PlayerData.GetDefaultData())
	invalidCoins.Coins = GameConfig.Player.MaxCoins + 1
	expect(not PlayerData.ValidateData(invalidCoins), "coins above maximum were accepted")

	local infiniteLevel = makeRecord(PlayerData.GetDefaultData())
	infiniteLevel.Level = math.huge
	expect(not PlayerData.ValidateData(infiniteLevel), "infinite level was accepted")

	local nanExperience = makeRecord(PlayerData.GetDefaultData())
	nanExperience.Experience = math.sqrt(-1)
	expect(not PlayerData.ValidateData(nanExperience), "NaN experience was accepted")
end)

addCase("ValidateData rejects invalid catalog references and nested fields", function()
	local unknownItem = makeValidData()
	unknownItem.Inventory.unknown_item = 1
	expect(not PlayerData.ValidateData(unknownItem), "unknown inventory item was accepted")

	local unknownCrop = makeValidData()
	unknownCrop.FarmPlots.plot_a.CropId = "unknown_crop"
	expect(not PlayerData.ValidateData(unknownCrop), "unknown crop was accepted")

	local invalidObjective = makeValidData()
	invalidObjective.ActiveQuests.gather_fiber.Objectives.unknown_objective = 1
	expect(not PlayerData.ValidateData(invalidObjective), "unknown quest objective was accepted")
end)

addCase("DecodeStoredData accepts and copies a valid current record", function()
	local original = makeValidData()
	local decoded, decodeError = PlayerData.DecodeStoredData(original)

	expect(decoded ~= nil, "current record was rejected: " .. tostring(decodeError))
	expect(decodeError == nil, "valid current record returned an error")
	expect(decoded ~= original, "current record was not copied")
	expect(PlayerData.DataEquals(decoded :: Data, original), "decoded current record differs from its source")
end)

addCase("DecodeStoredData preserves compatible legacy values exactly", function()
	local legacy: { [string]: unknown } = {
		Level = 7,
		Experience = GameConfig.Player.MaxExperience,
		Coins = GameConfig.Player.MaxCoins,
	}
	local decoded, decodeError = PlayerData.DecodeStoredData(legacy)

	expect(decoded ~= nil, "compatible legacy record was rejected: " .. tostring(decodeError))
	expect(decoded ~= nil and decoded.Level == legacy.Level, "legacy level changed during migration")
	expect(decoded ~= nil and decoded.Experience == legacy.Experience, "legacy experience changed during migration")
	expect(decoded ~= nil and decoded.Coins == legacy.Coins, "legacy coins changed during migration")
	expect(decoded ~= nil and decoded.SchemaVersion == GameConfig.SchemaVersion, "legacy schema was not upgraded")
end)

addCase("DecodeStoredData rejects invalid legacy and unknown schema records", function()
	local invalidLegacy: { [string]: unknown } = {
		Level = 0,
		Experience = 0,
		Coins = 0,
	}
	local invalidLegacyData = PlayerData.DecodeStoredData(invalidLegacy)
	expect(invalidLegacyData == nil, "invalid legacy record was accepted")

	local unknownVersion = makeRecord(PlayerData.GetDefaultData())
	unknownVersion.SchemaVersion = GameConfig.SchemaVersion + 1
	local unknownVersionData = PlayerData.DecodeStoredData(unknownVersion)
	expect(unknownVersionData == nil, "unknown schema version was accepted")

	local invalidCurrent = makeRecord(PlayerData.GetDefaultData())
	invalidCurrent.Inventory = "not an inventory table"
	local invalidCurrentData = PlayerData.DecodeStoredData(invalidCurrent)
	expect(invalidCurrentData == nil, "malformed current record was accepted")
end)

addCase("CloneData isolates nested inventory, plot, and quest tables", function()
	local original = makeValidData()
	local copy = PlayerData.CloneData(original)

	copy.Inventory.wheat_seed = 9
	copy.FarmPlots.plot_a.PlantedAt = 200
	copy.ActiveQuests.gather_fiber.Objectives.collect_fiber = 3
	copy.CompletedQuests.reach_level_2 = false

	expect(original.Inventory.wheat_seed == 2, "inventory mutation reached the original")
	expect(original.FarmPlots.plot_a.PlantedAt == 100, "plot mutation reached the original")
	expect(original.ActiveQuests.gather_fiber.Objectives.collect_fiber == 2, "objective mutation reached the original")
	expect(original.CompletedQuests.reach_level_2, "completed quest mutation reached the original")
end)

addCase("DataEquals compares equivalent and different records", function()
	local original = makeValidData()
	local equivalent = PlayerData.CloneData(original)
	expect(PlayerData.DataEquals(original, equivalent), "equivalent copy was considered different")

	equivalent.ActiveQuests.gather_fiber.Objectives.collect_fiber += 1
	expect(not PlayerData.DataEquals(original, equivalent), "nested difference was not detected")
end)

function PlayerDataUnitTests.Run(): RunResult
	local passed = 0
	local failed = 0
	local failures: { string } = {}

	for _, testCase in testCases do
		local succeeded, failure = pcall(testCase.Run)
		if succeeded then
			passed += 1
		else
			failed += 1
			local failureMessage = testCase.Name .. ": " .. tostring(failure)
			table.insert(failures, failureMessage)
			warn("PlayerDataUnitTests | FAIL | " .. failureMessage)
		end
	end

	print(
		"PlayerDataUnitTests | Resultado: "
			.. tostring(passed)
			.. " aprobadas, "
			.. tostring(failed)
			.. " fallidas."
	)

	return {
		Passed = passed,
		Failed = failed,
		Failures = failures,
	}
end

return PlayerDataUnitTests
