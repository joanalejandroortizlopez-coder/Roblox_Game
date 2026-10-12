--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerData"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerDataService"))

type Data = PlayerData.Data
type Service = PlayerDataService.Service
type StoreAdapter = PlayerDataService.StoreAdapter

type FakeStoreState = {
	Records: { [string]: unknown },
	ReadFailuresRemaining: number,
	WriteFailuresRemaining: number,
	FailAfterNextWrite: boolean,
	UpdateCalls: number,
}

type FakeStore = {
	Adapter: StoreAdapter,
	State: FakeStoreState,
}

type TestCase = {
	Name: string,
	Run: (player: Player) -> (),
}

export type RunResult = {
	Passed: number,
	Failed: number,
	Failures: { string },
}

local PlayerDataServiceTests = {}
local testCases: { TestCase } = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function playerKey(player: Player): string
	return "Player_" .. tostring(player.UserId)
end

local function makeFakeStore(): FakeStore
	local state: FakeStoreState = {
		Records = {},
		ReadFailuresRemaining = 0,
		WriteFailuresRemaining = 0,
		FailAfterNextWrite = false,
		UpdateCalls = 0,
	}

	local adapter: StoreAdapter = {
		GetAsync = function(key: string): unknown
			if state.ReadFailuresRemaining > 0 then
				state.ReadFailuresRemaining -= 1
				error("Simulated GetAsync failure")
			end

			local value = state.Records[key]
			if typeof(value) == "table" then
				local decoded = PlayerData.DecodeStoredData(value)
				if decoded then
					return PlayerData.CloneData(decoded)
				end
			end
			return value
		end,
		UpdateAsync = function(key: string, transform: (currentValue: unknown) -> Data?): unknown
			state.UpdateCalls += 1
			if state.WriteFailuresRemaining > 0 then
				state.WriteFailuresRemaining -= 1
				error("Simulated UpdateAsync failure before commit")
			end

			local candidate = transform(state.Records[key])
			if not candidate then
				return nil
			end

			local persistedData = PlayerData.CloneData(candidate)
			state.Records[key] = persistedData
			if state.FailAfterNextWrite then
				state.FailAfterNextWrite = false
				error("Simulated ambiguous UpdateAsync result after commit")
			end

			return PlayerData.CloneData(persistedData)
		end,
	}

	return {
		Adapter = adapter,
		State = state,
	}
end

local function addCase(name: string, run: (player: Player) -> ())
	table.insert(testCases, {
		Name = name,
		Run = run,
	})
end

addCase("new player loads defaults and saves updated data", function(player: Player)
	local fake = makeFakeStore()
	local service = PlayerDataService.CreateIsolated(fake.Adapter)
	local loaded, data, loadError = service.Load(player)
	expect(loaded and data ~= nil, "new profile failed to load: " .. tostring(loadError))
	expect(PlayerData.ValidateData(data), "new profile defaults failed validation")
	expect(data.Coins == 0, "new profile did not use the configured default coins")

	local updated, _, updateError = service.Update(player, function(candidate: Data): (boolean, string?)
		candidate.Coins = 37
		return true, nil
	end)
	expect(updated, "valid update failed: " .. tostring(updateError))

	local saved, saveError = service.Save(player)
	expect(saved, "save was not confirmed: " .. tostring(saveError))
	local storedData = PlayerData.DecodeStoredData(fake.State.Records[playerKey(player)])
	expect(storedData ~= nil and storedData.Coins == 37, "fake store did not retain the updated value")
	service.Remove(player)
end)

addCase("invalid stored data is rejected and the session is not operable", function(player: Player)
	local fake = makeFakeStore()
	local invalidData = PlayerData.GetDefaultData()
	invalidData.Level = 0
	fake.State.Records[playerKey(player)] = invalidData
	local service = PlayerDataService.CreateIsolated(fake.Adapter)

	local loaded = service.Load(player)
	expect(not loaded, "invalid stored profile was accepted")
	expect(service.Get(player) == nil, "failed session returned profile data")
	local saved = service.Save(player)
	expect(not saved, "failed session was allowed to save")
	local updated = service.Update(player, function(candidate: Data): (boolean, string?)
		candidate.Coins += 1
		return true, nil
	end)
	expect(not updated, "failed session was allowed to update")
	service.Remove(player)
end)

addCase("read errors eventually mark the session failed", function(player: Player)
	local fake = makeFakeStore()
	fake.State.ReadFailuresRemaining = 10
	local service = PlayerDataService.CreateIsolated(fake.Adapter)

	local loaded, _, loadError = service.Load(player)
	expect(not loaded, "read errors unexpectedly loaded a profile")
	expect(loadError ~= nil, "read failure did not return an error")
	expect(service.Get(player) == nil, "read failure exposed session data")
	service.Remove(player)
end)

addCase("write errors do not report success or commit changes", function(player: Player)
	local fake = makeFakeStore()
	fake.State.WriteFailuresRemaining = 10
	local service = PlayerDataService.CreateIsolated(fake.Adapter)
	local loaded, _, loadError = service.Load(player)
	expect(loaded, "new profile failed to load: " .. tostring(loadError))

	local updated, _, updateError = service.Update(player, function(candidate: Data): (boolean, string?)
		candidate.Coins = 91
		return true, nil
	end)
	expect(updated, "valid update failed: " .. tostring(updateError))

	local saved = service.Save(player)
	expect(not saved, "failed writes were reported as successful")
	expect(fake.State.Records[playerKey(player)] == nil, "failed writes changed the fake persisted record")
	local sessionData = service.Get(player)
	expect(sessionData ~= nil and sessionData.Coins == 91, "write failure discarded in-memory data")
	service.Remove(player)
end)

addCase("update is rejected before the session loads", function(player: Player)
	local fake = makeFakeStore()
	local service = PlayerDataService.CreateIsolated(fake.Adapter)

	local updated, _, updateError = service.Update(player, function(candidate: Data): (boolean, string?)
		candidate.Coins += 1
		return true, nil
	end)
	expect(not updated, "update succeeded without a loaded session")
	expect(updateError ~= nil, "rejected update did not explain the failure")
	expect(fake.State.UpdateCalls == 0, "unloaded update called the fake store")
end)

addCase("isolated instances do not share session data", function(player: Player)
	local fake = makeFakeStore()
	local firstService = PlayerDataService.CreateIsolated(fake.Adapter)
	local secondService = PlayerDataService.CreateIsolated(fake.Adapter)

	local firstLoaded, _, firstError = firstService.Load(player)
	local secondLoaded, _, secondError = secondService.Load(player)
	expect(firstLoaded, "first isolated session failed to load: " .. tostring(firstError))
	expect(secondLoaded, "second isolated session failed to load: " .. tostring(secondError))

	local updated, _, updateError = firstService.Update(player, function(candidate: Data): (boolean, string?)
		candidate.Coins = 12
		return true, nil
	end)
	expect(updated, "first isolated session update failed: " .. tostring(updateError))

	local firstData = firstService.Get(player)
	local secondData = secondService.Get(player)
	expect(firstData ~= nil and firstData.Coins == 12, "first service did not retain its own update")
	expect(secondData ~= nil and secondData.Coins == 0, "second service observed the first service session update")
	firstService.Remove(player)
	secondService.Remove(player)
end)

addCase("ambiguous write is confirmed only after a later successful response", function(player: Player)
	local fake = makeFakeStore()
	fake.State.FailAfterNextWrite = true
	local service = PlayerDataService.CreateIsolated(fake.Adapter)
	local loaded, _, loadError = service.Load(player)
	expect(loaded, "new profile failed to load: " .. tostring(loadError))

	local updated, _, updateError = service.Update(player, function(candidate: Data): (boolean, string?)
		candidate.Coins = 53
		return true, nil
	end)
	expect(updated, "valid update failed: " .. tostring(updateError))

	local saved, saveError = service.Save(player)
	expect(saved, "ambiguous write was not confirmed by retry: " .. tostring(saveError))
	expect(fake.State.UpdateCalls >= 2, "ambiguous write did not exercise a retry")
	local storedData = PlayerData.DecodeStoredData(fake.State.Records[playerKey(player)])
	expect(storedData ~= nil and storedData.Coins == 53, "candidate was not persisted in memory")
	service.Remove(player)
end)

function PlayerDataServiceTests.Run(): RunResult
	local players = Players:GetPlayers()
	local player = players[1]
	if not player then
		local message = "Run requires an active Studio player; no tests were started."
		warn("PlayerDataServiceTests | " .. message)
		return {
			Passed = 0,
			Failed = 1,
			Failures = { message },
		}
	end

	local passed = 0
	local failed = 0
	local failures: { string } = {}
	for _, testCase in testCases do
		local succeeded, failure = pcall(testCase.Run, player)
		if succeeded then
			passed += 1
		else
			failed += 1
			local failureMessage = testCase.Name .. ": " .. tostring(failure)
			table.insert(failures, failureMessage)
			warn("PlayerDataServiceTests | FAIL | " .. failureMessage)
		end
	end

	print(
		"PlayerDataServiceTests | Resultado: "
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

return PlayerDataServiceTests
