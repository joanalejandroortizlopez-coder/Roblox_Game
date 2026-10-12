--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CropDefinitions = require(Shared:WaitForChild("CropDefinitions"))
local InventoryService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("InventoryService"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerDataService"))

type Data = PlayerData.Data

local FarmingService = {}
local randomGenerator = Random.new()

export type PlotStatus = {
	PlotId: string,
	CropId: string,
	PlantedAt: number,
	Ready: boolean,
	SecondsRemaining: number,
}

local function isValidPlotId(plotId: string): boolean
	return typeof(plotId) == "string"
		and #plotId > 0
		and #plotId <= GameConfig.Farming.MaxPlotIdLength
		and string.match(plotId, "^[%w_%-]+$") ~= nil
end

function FarmingService.CanPlant(player: Player, plotId: string, cropId: string): (boolean, string?)
	if not isValidPlotId(plotId) then
		return false, "El identificador de parcela no es válido."
	end

	local crop = if typeof(cropId) == "string" then CropDefinitions.Get(cropId) else nil
	if not crop then
		return false, "El identificador del cultivo no existe."
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return false, "Los datos del jugador no están cargados."
	end
	if data.FarmPlots[plotId] then
		return false, "La parcela ya está ocupada."
	end
	if data.Level < crop.MinLevel then
		return false, "El nivel del jugador no alcanza el requisito del cultivo."
	end
	if (data.Inventory[crop.SeedItemId] or 0) < 1 then
		return false, "No hay semillas suficientes."
	end
	if data.FarmPlots[plotId] == nil then
		local plotCount = 0
		for _ in data.FarmPlots do
			plotCount += 1
		end
		if plotCount >= GameConfig.Farming.MaxStoredPlots then
			return false, "Se alcanzó el máximo de parcelas registradas."
		end
	end
	return true, nil
end

function FarmingService.Plant(player: Player, plotId: string, cropId: string): (boolean, string?)
	if not isValidPlotId(plotId) then
		return false, "El identificador de parcela no es válido."
	end
	local crop = if typeof(cropId) == "string" then CropDefinitions.Get(cropId) else nil
	if not crop then
		return false, "El identificador del cultivo no existe."
	end

	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		if data.FarmPlots[plotId] then
			return false, "La parcela ya está ocupada."
		end
		if data.Level < crop.MinLevel then
			return false, "El nivel del jugador no alcanza el requisito del cultivo."
		end

		local plotCount = 0
		for _ in data.FarmPlots do
			plotCount += 1
		end
		if plotCount >= GameConfig.Farming.MaxStoredPlots then
			return false, "Se alcanzó el máximo de parcelas registradas."
		end

		local seedRemoved, removeError = InventoryService.RemoveFromData(data, crop.SeedItemId, 1)
		if not seedRemoved then
			return false, removeError
		end

		data.FarmPlots[plotId] = {
			CropId = crop.Id,
			PlantedAt = os.time(),
		}
		return true, nil
	end)
	return success, updateError
end

function FarmingService.GetPlotStatus(player: Player, plotId: string): (boolean, PlotStatus?, string?)
	if not isValidPlotId(plotId) then
		return false, nil, "El identificador de parcela no es válido."
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return false, nil, "Los datos del jugador no están cargados."
	end

	local plot = data.FarmPlots[plotId]
	if not plot then
		return false, nil, "La parcela está vacía."
	end

	local crop = CropDefinitions.Get(plot.CropId)
	if not crop then
		return false, nil, "El cultivo guardado ya no está definido."
	end

	local elapsed = math.max(0, os.time() - plot.PlantedAt)
	local secondsRemaining = math.max(0, crop.GrowthSeconds - elapsed)
	return true, {
		PlotId = plotId,
		CropId = plot.CropId,
		PlantedAt = plot.PlantedAt,
		Ready = secondsRemaining == 0,
		SecondsRemaining = secondsRemaining,
	}, nil
end

function FarmingService.Harvest(player: Player, plotId: string): (boolean, number?, string?)
	if not isValidPlotId(plotId) then
		return false, nil, "El identificador de parcela no es válido."
	end

	local harvestedQuantity: number? = nil
	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		local plot = data.FarmPlots[plotId]
		if not plot then
			return false, "La parcela está vacía."
		end

		local crop = CropDefinitions.Get(plot.CropId)
		if not crop then
			return false, "El cultivo guardado ya no está definido."
		end
		if os.time() < plot.PlantedAt + crop.GrowthSeconds then
			return false, "El cultivo todavía no está listo."
		end

		local quantity = randomGenerator:NextInteger(crop.MinYield, crop.MaxYield)
		local added, addError = InventoryService.AddToData(data, crop.ProductItemId, quantity)
		if not added then
			return false, addError
		end

		data.FarmPlots[plotId] = nil
		harvestedQuantity = quantity
		return true, nil
	end)

	if not success then
		return false, nil, updateError
	end
	return true, harvestedQuantity, nil
end

return FarmingService
