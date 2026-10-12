--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerDataService"))

type Data = PlayerData.Data

local EconomyService = {}

local function isValidAmount(amount: number): boolean
	return typeof(amount) == "number"
		and amount == amount
		and amount > -math.huge
		and amount < math.huge
		and amount % 1 == 0
		and amount > 0
		and amount <= GameConfig.Player.MaxCoins
end

function EconomyService.GetCoins(player: Player): (boolean, number?, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, nil, "Los datos del jugador no están cargados."
	end
	return true, data.Coins, nil
end

function EconomyService.AddCoinsToData(data: Data, amount: number): (boolean, string?)
	if not isValidAmount(amount) then
		return false, "El importe debe ser un entero finito positivo dentro del límite permitido."
	end
	if data.Coins > GameConfig.Player.MaxCoins - amount then
		return false, "La operación superaría el límite máximo de monedas."
	end
	data.Coins += amount
	return true, nil
end

function EconomyService.SpendCoinsFromData(data: Data, amount: number): (boolean, string?)
	if not isValidAmount(amount) then
		return false, "El importe debe ser un entero finito positivo dentro del límite permitido."
	end
	if data.Coins < amount then
		return false, "No hay monedas suficientes."
	end
	data.Coins -= amount
	return true, nil
end

function EconomyService.AddCoins(player: Player, amount: number): (boolean, string?)
	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		return EconomyService.AddCoinsToData(data, amount)
	end)
	return success, updateError
end

function EconomyService.SpendCoins(player: Player, amount: number): (boolean, string?)
	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		return EconomyService.SpendCoinsFromData(data, amount)
	end)
	return success, updateError
end

return EconomyService
