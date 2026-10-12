--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local QuestDefinitions = require(Shared:WaitForChild("QuestDefinitions"))
local EconomyService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("EconomyService"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerDataService"))
local ProgressionService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("ProgressionService"))

type Data = PlayerData.Data

local QuestService = {}

export type ObjectiveEvent = QuestDefinitions.ObjectiveEvent
export type ActiveProgress = {
	QuestId: string,
	Objectives: { [string]: number },
	Complete: boolean,
}

local function prerequisitesMet(data: Data, quest: QuestDefinitions.Definition): boolean
	for _, prerequisiteId in quest.Prerequisites do
		if data.CompletedQuests[prerequisiteId] ~= true then
			return false
		end
	end
	return true
end

local function isComplete(quest: QuestDefinitions.Definition, progress: { [string]: number }): boolean
	for _, objective in quest.Objectives do
		if (progress[objective.Id] or 0) ~= objective.RequiredAmount then
			return false
		end
	end
	return true
end

local function isValidProgressAmount(amount: number): boolean
	return typeof(amount) == "number"
		and amount == amount
		and amount > -math.huge
		and amount < math.huge
		and amount % 1 == 0
		and amount > 0
		and amount <= GameConfig.Quests.MaxProgressPerAction
end

function QuestService.GetAvailable(player: Player): (boolean, { QuestDefinitions.Definition }?, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, nil, "Los datos del jugador no están cargados."
	end

	local available: { QuestDefinitions.Definition } = {}
	for _, quest in QuestDefinitions.GetAll() do
		if data.ActiveQuests[quest.Id] == nil
			and data.CompletedQuests[quest.Id] ~= true
			and prerequisitesMet(data, quest)
		then
			table.insert(available, quest)
		end
	end
	return true, available, nil
end

function QuestService.GetActiveProgress(player: Player, questId: string): (boolean, ActiveProgress?, string?)
	local quest = if typeof(questId) == "string" then QuestDefinitions.Get(questId) else nil
	if not quest then
		return false, nil, "El identificador de misión no existe."
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return false, nil, "Los datos del jugador no están cargados."
	end

	local savedProgress = data.ActiveQuests[questId]
	if not savedProgress then
		return false, nil, "La misión no está activa."
	end

	local objectives: { [string]: number } = {}
	for objectiveId, amount in savedProgress.Objectives do
		objectives[objectiveId] = amount
	end
	return true, {
		QuestId = questId,
		Objectives = objectives,
		Complete = isComplete(quest, objectives),
	}, nil
end

function QuestService.Accept(player: Player, questId: string): (boolean, string?)
	local quest = if typeof(questId) == "string" then QuestDefinitions.Get(questId) else nil
	if not quest then
		return false, "El identificador de misión no existe."
	end

	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		if data.ActiveQuests[questId] or data.CompletedQuests[questId] then
			return false, "La misión ya está activa o fue completada."
		end
		if not prerequisitesMet(data, quest) then
			return false, "No se han completado los requisitos previos."
		end

		local activeCount = 0
		for _ in data.ActiveQuests do
			activeCount += 1
		end
		if activeCount >= GameConfig.Quests.MaxActiveQuests then
			return false, "Se alcanzó el límite de misiones activas."
		end

		local objectives: { [string]: number } = {}
		for _, objective in quest.Objectives do
			objectives[objective.Id] = 0
		end
		data.ActiveQuests[questId] = { Objectives = objectives }
		return true, nil
	end)
	return success, updateError
end

function QuestService.RecordProgress(
	player: Player,
	event: ObjectiveEvent,
	targetId: string,
	amount: number
): (boolean, number?, string?)
	if not isValidProgressAmount(amount) then
		return false, nil, "La cantidad de progreso debe ser un entero finito positivo dentro del límite permitido."
	end
	if typeof(targetId) ~= "string" or #targetId == 0 or #targetId > GameConfig.Inventory.MaxItemIdLength then
		return false, nil, "El objetivo del evento no es válido."
	end
	if event ~= "CollectItem" and event ~= "HarvestCrop" and event ~= "ReachLevel" then
		return false, nil, "El tipo de evento no es válido."
	end

	local changedAmount = 0
	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		for questId, savedProgress in data.ActiveQuests do
			local quest = QuestDefinitions.Get(questId)
			if quest then
				for _, objective in quest.Objectives do
					if objective.Event == event and objective.TargetId == targetId then
						local previous = savedProgress.Objectives[objective.Id] or 0
					local nextAmount = math.min(objective.RequiredAmount, previous + amount)
					if nextAmount > previous then
						changedAmount += nextAmount - previous
						savedProgress.Objectives[objective.Id] = nextAmount
					end
				end
				end
			end
		end
		return true, nil
	end)

	if not success then
		return false, nil, updateError
	end
	return true, changedAmount, nil
end

function QuestService.ClaimRewards(player: Player, questId: string): (boolean, string?)
	local quest = if typeof(questId) == "string" then QuestDefinitions.Get(questId) else nil
	if not quest then
		return false, "El identificador de misión no existe."
	end

	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		local savedProgress = data.ActiveQuests[questId]
		if not savedProgress then
			return false, "La misión no está activa o sus recompensas ya se reclamaron."
		end
		if not isComplete(quest, savedProgress.Objectives) then
			return false, "La misión todavía no está completa."
		end

		local completedCount = 0
		for _ in data.CompletedQuests do
			completedCount += 1
		end
		if completedCount >= GameConfig.Quests.MaxCompletedQuests then
			return false, "Se alcanzó el límite de misiones completadas almacenadas."
		end

		local experienceAdded, _, experienceError = ProgressionService.ApplyExperienceToData(data, quest.ExperienceReward)
		if not experienceAdded then
			return false, experienceError
		end
		local coinsAdded, coinsError = EconomyService.AddCoinsToData(data, quest.CoinsReward)
		if not coinsAdded then
			return false, coinsError
		end

		data.ActiveQuests[questId] = nil
		data.CompletedQuests[questId] = true
		return true, nil
	end)
	return success, updateError
end

return QuestService
