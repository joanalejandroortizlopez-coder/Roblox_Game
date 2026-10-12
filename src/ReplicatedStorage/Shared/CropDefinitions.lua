--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))

local CropDefinitions = {}

export type Definition = {
	Id: string,
	DisplayName: string,
	SeedItemId: string,
	ProductItemId: string,
	GrowthSeconds: number,
	MinYield: number,
	MaxYield: number,
	MinLevel: number,
}

local definitions: { [string]: Definition } = {
	wheat = {
		Id = "wheat",
		DisplayName = "Trigo",
		SeedItemId = "wheat_seed",
		ProductItemId = "wheat",
		GrowthSeconds = 60,
		MinYield = 1,
		MaxYield = 3,
		MinLevel = 1,
	},
	carrot = {
		Id = "carrot",
		DisplayName = "Zanahoria",
		SeedItemId = "carrot_seed",
		ProductItemId = "carrot",
		GrowthSeconds = 90,
		MinYield = 1,
		MaxYield = 3,
		MinLevel = 1,
	},
	tomato = {
		Id = "tomato",
		DisplayName = "Tomate",
		SeedItemId = "tomato_seed",
		ProductItemId = "tomato",
		GrowthSeconds = 120,
		MinYield = 1,
		MaxYield = 2,
		MinLevel = 2,
	},
}

for cropId, definition in definitions do
	local seedDefinition = ItemDefinitions.Get(definition.SeedItemId)
	local productDefinition = ItemDefinitions.Get(definition.ProductItemId)
	if cropId ~= definition.Id
		or not seedDefinition
		or seedDefinition.Category ~= "Seed"
		or not productDefinition
		or productDefinition.Category ~= "Crop"
	then
		error("CropDefinitions contiene referencias de inventario inconsistentes para " .. cropId)
	end
	table.freeze(definition)
end

table.freeze(definitions)

function CropDefinitions.Get(cropId: string): Definition?
	return definitions[cropId]
end

function CropDefinitions.GetAll(): { Definition }
	local result: { Definition } = {}
	for _, definition in definitions do
		table.insert(result, definition)
	end
	table.sort(result, function(first: Definition, second: Definition): boolean
		return first.Id < second.Id
	end)
	return result
end

return CropDefinitions
