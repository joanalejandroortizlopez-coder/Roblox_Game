--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local ItemDefinitions = {}

export type Category = "Seed" | "Crop" | "Material" | "Consumable"
export type Definition = {
	Id: string,
	DisplayName: string,
	Category: Category,
	StackLimit: number,
}

local definitions: { [string]: Definition } = {
	wheat_seed = {
		Id = "wheat_seed",
		DisplayName = "Semilla de trigo",
		Category = "Seed",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	carrot_seed = {
		Id = "carrot_seed",
		DisplayName = "Semilla de zanahoria",
		Category = "Seed",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	tomato_seed = {
		Id = "tomato_seed",
		DisplayName = "Semilla de tomate",
		Category = "Seed",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	wheat = {
		Id = "wheat",
		DisplayName = "Trigo",
		Category = "Crop",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	carrot = {
		Id = "carrot",
		DisplayName = "Zanahoria",
		Category = "Crop",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	tomato = {
		Id = "tomato",
		DisplayName = "Tomate",
		Category = "Crop",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	wood = {
		Id = "wood",
		DisplayName = "Madera",
		Category = "Material",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	stone = {
		Id = "stone",
		DisplayName = "Piedra",
		Category = "Material",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	fiber = {
		Id = "fiber",
		DisplayName = "Fibra",
		Category = "Material",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
	basic_potion = {
		Id = "basic_potion",
		DisplayName = "Poción básica",
		Category = "Consumable",
		StackLimit = GameConfig.Inventory.MaxQuantityPerItem,
	},
}

for _, definition in definitions do
	table.freeze(definition)
end

table.freeze(definitions)

function ItemDefinitions.Get(itemId: string): Definition?
	return definitions[itemId]
end

function ItemDefinitions.IsValidId(itemId: string): boolean
	return definitions[itemId] ~= nil
end

function ItemDefinitions.GetAll(): { Definition }
	local result: { Definition } = {}
	for _, definition in definitions do
		table.insert(result, definition)
	end
	table.sort(result, function(first: Definition, second: Definition): boolean
		return first.Id < second.Id
	end)
	return result
end

return ItemDefinitions
