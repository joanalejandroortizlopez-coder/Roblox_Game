--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local CropDefinitions = require(Shared:WaitForChild("CropDefinitions"))

local QuestDefinitions = {}

export type ObjectiveEvent = "CollectItem" | "HarvestCrop" | "ReachLevel"
export type Objective = {
	Id: string,
	Event: ObjectiveEvent,
	TargetId: string,
	RequiredAmount: number,
}
export type Definition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Objectives: { Objective },
	ExperienceReward: number,
	CoinsReward: number,
	Prerequisites: { string },
}

local definitions: { [string]: Definition } = {
	gather_fiber = {
		Id = "gather_fiber",
		DisplayName = "Fibras para el camino",
		Description = "Reúne fibra para preparar tus suministros.",
		Objectives = {
			{ Id = "collect_fiber", Event = "CollectItem", TargetId = "fiber", RequiredAmount = 3 },
		},
		ExperienceReward = 60,
		CoinsReward = 25,
		Prerequisites = {},
	},
	harvest_wheat = {
		Id = "harvest_wheat",
		DisplayName = "Primera cosecha",
		Description = "Cosecha trigo para abastecer el asentamiento.",
		Objectives = {
			{ Id = "harvest_wheat", Event = "HarvestCrop", TargetId = "wheat", RequiredAmount = 3 },
		},
		ExperienceReward = 100,
		CoinsReward = 40,
		Prerequisites = { "gather_fiber" },
	},
	reach_level_2 = {
		Id = "reach_level_2",
		DisplayName = "Nuevos horizontes",
		Description = "Alcanza el nivel 2.",
		Objectives = {
			{ Id = "reach_level_2", Event = "ReachLevel", TargetId = "2", RequiredAmount = 1 },
		},
		ExperienceReward = 120,
		CoinsReward = 50,
		Prerequisites = {},
	},
}

for questId, definition in definitions do
	if questId ~= definition.Id then
		error("QuestDefinitions contiene un ID inconsistente: " .. questId)
	end
	for _, objective in definition.Objectives do
		if objective.Event == "CollectItem" and not ItemDefinitions.IsValidId(objective.TargetId) then
			error("QuestDefinitions referencia un objeto desconocido: " .. objective.TargetId)
		elseif objective.Event == "HarvestCrop" and not CropDefinitions.Get(objective.TargetId) then
			error("QuestDefinitions referencia un cultivo desconocido: " .. objective.TargetId)
		end
		table.freeze(objective)
	end
	table.freeze(definition.Objectives)
	table.freeze(definition.Prerequisites)
	table.freeze(definition)
end

table.freeze(definitions)

function QuestDefinitions.Get(questId: string): Definition?
	return definitions[questId]
end

function QuestDefinitions.GetAll(): { Definition }
	local result: { Definition } = {}
	for _, definition in definitions do
		table.insert(result, definition)
	end
	table.sort(result, function(first: Definition, second: Definition): boolean
		return first.Id < second.Id
	end)
	return result
end

return QuestDefinitions
