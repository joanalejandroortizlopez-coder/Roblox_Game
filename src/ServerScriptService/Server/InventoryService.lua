--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerDataService"))

type Data = PlayerData.Data

local InventoryService = {}

local function isValidQuantity(quantity: number): boolean
	return typeof(quantity) == "number"
		and quantity == quantity
		and quantity > -math.huge
		and quantity < math.huge
		and quantity % 1 == 0
		and quantity > 0
		and quantity <= GameConfig.Inventory.MaxQuantityPerItem
end

function InventoryService.GetCapacity(): number
	return GameConfig.Inventory.InitialCapacity
end

function InventoryService.GetInventory(player: Player): (boolean, { [string]: number }?, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, nil, "Los datos del jugador no están cargados."
	end

	local inventory: { [string]: number } = {}
	for itemId, quantity in data.Inventory do
		inventory[itemId] = quantity
	end
	return true, inventory, nil
end

function InventoryService.GetQuantity(player: Player, itemId: string): (boolean, number?, string?)
	if typeof(itemId) ~= "string" or not ItemDefinitions.IsValidId(itemId) then
		return false, nil, "El identificador del objeto no es válido."
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return false, nil, "Los datos del jugador no están cargados."
	end
	return true, data.Inventory[itemId] or 0, nil
end

function InventoryService.AddToData(data: Data, itemId: string, quantity: number): (boolean, string?)
	local definition = if typeof(itemId) == "string" then ItemDefinitions.Get(itemId) else nil
	if not definition then
		return false, "El identificador del objeto no existe en el catálogo."
	end
	if not isValidQuantity(quantity) then
		return false, "La cantidad debe ser un entero finito positivo dentro del límite permitido."
	end

	local currentQuantity = data.Inventory[itemId] or 0
	if currentQuantity > definition.StackLimit - quantity then
		return false, "La pila superaría la cantidad máxima permitida para el objeto."
	end

	if currentQuantity == 0 then
		local occupiedSlots = 0
		for _ in data.Inventory do
			occupiedSlots += 1
		end
		if occupiedSlots >= InventoryService.GetCapacity() then
			return false, "No hay espacios de inventario disponibles."
		end
	end

	data.Inventory[itemId] = currentQuantity + quantity
	return true, nil
end

function InventoryService.RemoveFromData(data: Data, itemId: string, quantity: number): (boolean, string?)
	if typeof(itemId) ~= "string" or not ItemDefinitions.IsValidId(itemId) then
		return false, "El identificador del objeto no existe en el catálogo."
	end
	if not isValidQuantity(quantity) then
		return false, "La cantidad debe ser un entero finito positivo dentro del límite permitido."
	end

	local currentQuantity = data.Inventory[itemId] or 0
	if currentQuantity < quantity then
		return false, "No hay unidades suficientes del objeto."
	end

	local remaining = currentQuantity - quantity
	if remaining == 0 then
		data.Inventory[itemId] = nil
	else
		data.Inventory[itemId] = remaining
	end
	return true, nil
end

function InventoryService.AddItem(player: Player, itemId: string, quantity: number): (boolean, string?)
	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		return InventoryService.AddToData(data, itemId, quantity)
	end)
	return success, updateError
end

function InventoryService.RemoveItem(player: Player, itemId: string, quantity: number): (boolean, string?)
	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		return InventoryService.RemoveFromData(data, itemId, quantity)
	end)
	return success, updateError
end

return InventoryService
