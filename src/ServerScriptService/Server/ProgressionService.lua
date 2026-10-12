--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerDataService"))

type Data = PlayerData.Data

local ProgressionService = {}

export type Progress = {
	Level: number,
	Experience: number,
	ExperienceRequired: number,
	Fraction: number,
}
export type GrantResult = {
	ExperienceAdded: number,
	LevelBefore: number,
	LevelAfter: number,
	Experience: number,
}

local function isValidGrant(amount: number): boolean
	return typeof(amount) == "number"
		and amount == amount
		and amount > -math.huge
		and amount < math.huge
		and amount % 1 == 0
		and amount >= 0
		and amount <= GameConfig.Progression.MaxGrantPerAction
end

function ProgressionService.ExperienceForNextLevel(level: number): number?
	if typeof(level) ~= "number"
		or level ~= level
		or level % 1 ~= 0
		or level < 1
		or level > GameConfig.Player.MaxLevel
	then
		return nil
	end

	if level >= GameConfig.Player.MaxLevel then
		return 0
	end

	return GameConfig.Progression.BaseExperience
		+ level * GameConfig.Progression.LinearExperiencePerLevel
		+ level * level * GameConfig.Progression.QuadraticExperiencePerLevel
end

local function applyValidatedExperience(data: Data, amount: number): GrantResult
	local levelBefore = data.Level
	local remainingGrant = amount
	local experience = data.Experience

	while data.Level < GameConfig.Player.MaxLevel do
		local required = ProgressionService.ExperienceForNextLevel(data.Level) :: number
		if experience >= required then
			experience -= required
			data.Level += 1
			continue
		end

		local needed = required - experience
		if remainingGrant >= needed then
			remainingGrant -= needed
			experience = 0
			data.Level += 1
		else
			experience += remainingGrant
			remainingGrant = 0
			break
		end
	end

	data.Experience = if data.Level >= GameConfig.Player.MaxLevel then 0 else experience
	return {
		ExperienceAdded = amount - remainingGrant,
		LevelBefore = levelBefore,
		LevelAfter = data.Level,
		Experience = data.Experience,
	}
end

function ProgressionService.GetProgress(player: Player): (boolean, Progress?, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, nil, "Los datos del jugador no están cargados."
	end

	local normalizedData = PlayerData.CloneData(data)
	applyValidatedExperience(normalizedData, 0)

	local required = ProgressionService.ExperienceForNextLevel(normalizedData.Level)
	if required == nil then
		return false, nil, "El nivel guardado no es válido."
	end

	return true, {
		Level = normalizedData.Level,
		Experience = normalizedData.Experience,
		ExperienceRequired = required,
		Fraction = if required == 0 then 1 else normalizedData.Experience / required,
	}, nil
end

function ProgressionService.ApplyExperienceToData(data: Data, amount: number): (boolean, GrantResult?, string?)
	if not isValidGrant(amount) then
		return false, nil, "La cantidad de experiencia debe ser un entero finito dentro del límite permitido."
	end

	return true, applyValidatedExperience(data, amount), nil
end

function ProgressionService.AddExperience(player: Player, amount: number): (boolean, GrantResult?, string?)
	local result: GrantResult? = nil
	local success, _, updateError = PlayerDataService.Update(player, function(data: Data): (boolean, string?)
		local grantSucceeded, grantResult, grantError = ProgressionService.ApplyExperienceToData(data, amount)
		if not grantSucceeded then
			return false, grantError
		end
		result = grantResult
		return true, nil
	end)

	if not success then
		return false, nil, updateError
	end
	return true, result, nil
end

return ProgressionService
