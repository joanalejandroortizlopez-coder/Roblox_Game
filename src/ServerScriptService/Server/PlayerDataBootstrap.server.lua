--!strict

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(
    ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerDataService")
)

local initializedPlayers: { [Player]: boolean } = {}
local loadingPlayers: { [Player]: boolean } = {}
local trackedPlayers: { [Player]: boolean } = {}
local shuttingDown = false
local shutdownDeadline: number? = nil

local function onPlayerAdded(player: Player)
    if shuttingDown or initializedPlayers[player] then
        if shuttingDown and player.Parent == Players then
            player:Kick("El servidor se está cerrando. Inténtalo de nuevo en unos momentos.")
        end
        return
    end

    initializedPlayers[player] = true
    loadingPlayers[player] = true

    local callSucceeded, loadSucceeded, loadError = pcall(function(): (boolean, string?)
        local succeeded, _loadedData, message = PlayerDataService.Load(player)
        return succeeded, message
    end)
    loadingPlayers[player] = nil

    if not callSucceeded or not loadSucceeded then
        PlayerDataService.Remove(player)
        local reason = if callSucceeded then tostring(loadError) else tostring(loadSucceeded)
        warn("PlayerDataBootstrap | Error al cargar datos de " .. player.Name .. ": " .. reason)
        if player.Parent == Players then
            player:Kick("No se pudieron cargar tus datos de forma segura. Vuelve a intentarlo más tarde.")
        end
        return
    end

    if player.Parent ~= Players then
        PlayerDataService.Remove(player)
        return
    end

    trackedPlayers[player] = true
    print("PlayerDataBootstrap | Datos cargados para " .. player.Name)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
    task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
    initializedPlayers[player] = nil

    if PlayerDataService.Get(player) == nil then
        PlayerDataService.Remove(player)
        return
    end

    trackedPlayers[player] = true
    local saveSucceeded: boolean
    local saveError: string?
    local activeShutdownDeadline = shutdownDeadline
    if activeShutdownDeadline then
        saveSucceeded, saveError = PlayerDataService.Save(player, activeShutdownDeadline)
    else
        saveSucceeded, saveError = PlayerDataService.Save(player)
    end
    if saveSucceeded then
        trackedPlayers[player] = nil
        PlayerDataService.Remove(player)
        print("PlayerDataBootstrap | Datos guardados para " .. player.Name)
    else
        warn("PlayerDataBootstrap | Error al guardar datos de " .. player.Name .. ": " .. tostring(saveError))
    end
end)

game:BindToClose(function()
    shuttingDown = true
    local closeDeadline = os.clock() + 25
    shutdownDeadline = closeDeadline
    local loadWaitDeadline = closeDeadline - 10

    while next(loadingPlayers) ~= nil and os.clock() < loadWaitDeadline do
        task.wait(0.1)
    end

    for _, player in Players:GetPlayers() do
        if PlayerDataService.Get(player) ~= nil then
            trackedPlayers[player] = true
        end
    end

    local pendingSaves = 0
    local unstartedSaves = 0
    for player in trackedPlayers do
        if PlayerDataService.Get(player) == nil then
            trackedPlayers[player] = nil
        elseif os.clock() >= closeDeadline then
            unstartedSaves += 1
        else
            pendingSaves += 1
            task.spawn(function()
                local saveSucceeded, saveError = PlayerDataService.Save(player, closeDeadline)
                if saveSucceeded then
                    trackedPlayers[player] = nil
                    PlayerDataService.Remove(player)
                else
                    warn("PlayerDataBootstrap | Error al guardar durante el cierre para " .. player.Name .. ": " .. tostring(saveError))
                end
                pendingSaves -= 1
            end)
        end
    end

    while pendingSaves > 0 and os.clock() < closeDeadline do
        task.wait(0.1)
    end

    local savesStillInFlight = 0
    for player in trackedPlayers do
        if PlayerDataService.IsSaving(player) then
            savesStillInFlight += 1
        end
    end

    if pendingSaves > 0 or savesStillInFlight > 0 or unstartedSaves > 0 then
        warn(
            "PlayerDataBootstrap | Plazo de cierre agotado; quedan "
                .. tostring(pendingSaves)
                .. " tarea(s) de guardado pendientes, "
                .. tostring(savesStillInFlight)
                .. " llamada(s) de DataStore en curso y "
                .. tostring(unstartedSaves)
                .. " guardado(s) sin iniciar. Las llamadas ya iniciadas no se cancelan."
        )
    end
end)
