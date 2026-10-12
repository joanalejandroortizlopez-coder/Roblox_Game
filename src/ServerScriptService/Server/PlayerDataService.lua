--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerData")
)

type Data = PlayerData.Data
type SessionStatus = "Loading" | "Loaded" | "Failed"
export type StoreAdapter = {
    GetAsync: (key: string) -> unknown,
    UpdateAsync: (key: string, transform: (currentValue: unknown) -> Data?) -> unknown,
}

type Session = {
    status: SessionStatus,
    data: Data?,
    baseline: Data?,
    baselineAbsent: boolean,
    loadError: string?,
    saveBlocked: boolean,
    blockedReason: string?,
    saving: boolean,
    saveSucceeded: boolean,
    lastSaveError: string?,
    removeRequested: boolean,
    updating: boolean,
    saveDeadline: number?,
}

export type Service = {
    Load: (player: Player) -> (boolean, Data?, string?),
    Get: (player: Player) -> Data?,
    Save: (player: Player, deadline: number?) -> (boolean, string?),
    Update: (player: Player, mutator: (Data) -> (boolean, string?)) -> (boolean, Data?, string?),
    IsSaving: (player: Player) -> boolean,
    Remove: (player: Player) -> (),
}

type StoreProvider = () -> (StoreAdapter?, string?)
type PlayerDataServiceModule = Service & {
    CreateIsolated: (store: StoreAdapter) -> Service,
}

local MAX_ATTEMPTS = 3
local RETRY_DELAY_SECONDS = 0.5
local SAVE_WAIT_TIMEOUT_SECONDS = 25

local productionStore: StoreAdapter? = nil
local productionStoreError: string? = nil
local productionStoreInitialized = false

local function getProductionStore(): (StoreAdapter?, string?)
    if not productionStoreInitialized then
        productionStoreInitialized = true
        local callSucceeded, result = pcall(function(): StoreAdapter
            local dataStoreService = game:GetService("DataStoreService")
            local store = dataStoreService:GetDataStore("RobloxRPG_PlayerData_v1")
            return {
                GetAsync = function(key: string): unknown
                    return store:GetAsync(key)
                end,
                UpdateAsync = function(
                    key: string,
                    transform: (currentValue: unknown) -> Data?
                ): unknown
                    return store:UpdateAsync(key, transform)
                end,
            }
        end)

        if callSucceeded then
            productionStore = result
        else
            productionStoreError = tostring(result)
        end
    end

    return productionStore, productionStoreError
end

local function cloneData(data: Data): Data
    return PlayerData.CloneData(data)
end

local function getKey(player: Player): string
    return "Player_" .. tostring(player.UserId)
end

local function stopSuspendedMutator(mutatorThread: thread): boolean
    if coroutine.status(mutatorThread) == "dead" then
        return true
    end

    local cancelCallSucceeded = pcall(task.cancel, mutatorThread)
    if cancelCallSucceeded and coroutine.status(mutatorThread) == "dead" then
        return true
    end

    local closeCallSucceeded = pcall(coroutine.close, mutatorThread)
    return closeCallSucceeded and coroutine.status(mutatorThread) == "dead"
end

local function createService(storeProvider: StoreProvider): Service
local sessions: { [Player]: Session } = {}
local service: Service = {}

function service.Load(player: Player): (boolean, Data?, string?)
    local existingSession = sessions[player]
    if existingSession then
        if existingSession.status == "Loaded" and existingSession.data then
            return true, cloneData(existingSession.data), nil
        end

        if existingSession.status == "Loading" then
            return false, nil, "La carga de datos ya está en curso."
        end

        return false, nil, existingSession.loadError or "La sesión de datos falló."
    end

    local session: Session = {
        status = "Loading",
        data = nil,
        baseline = nil,
        baselineAbsent = false,
        loadError = nil,
        saveBlocked = false,
        blockedReason = nil,
        saving = false,
        saveSucceeded = false,
        lastSaveError = nil,
        removeRequested = false,
        updating = false,
        saveDeadline = nil,
    }
    sessions[player] = session

    local store, storeError = storeProvider()
    if not store then
        session.status = "Failed"
        session.loadError = storeError or "No se pudo inicializar el almacén de datos."
        return false, nil, session.loadError
    end

    local lastError = "Error desconocido al cargar los datos."
    for attempt = 1, MAX_ATTEMPTS do
        local callSucceeded, storedValue = pcall(function()
            return store.GetAsync(getKey(player))
        end)

        if callSucceeded then
            local loadedData: Data
            if storedValue == nil then
                loadedData = PlayerData.GetDefaultData()
                session.baselineAbsent = true
            else
                local decodedData, decodeError = PlayerData.DecodeStoredData(storedValue)
                if not decodedData then
                    lastError = decodeError or "Los datos guardados no son válidos; no se sobrescribirán."
                    session.status = "Failed"
                    session.loadError = lastError
                    return false, nil, lastError
                end

                loadedData = decodedData
                session.baseline = PlayerData.CloneData(decodedData)
            end

            if sessions[player] ~= session or session.removeRequested or player.Parent ~= Players then
                if sessions[player] == session then
                    sessions[player] = nil
                end
                return false, nil, "El jugador salió mientras se cargaban sus datos."
            end

            session.data = loadedData
            session.status = "Loaded"
            return true, cloneData(loadedData), nil
        end

        lastError = tostring(storedValue)
        if attempt < MAX_ATTEMPTS then
            task.wait(RETRY_DELAY_SECONDS * attempt)
        end
    end

    if sessions[player] == session then
        session.status = "Failed"
        session.loadError = "No se pudieron cargar los datos después de varios intentos: " .. lastError
    end

    return false, nil, session.loadError or "La sesión terminó antes de completar la carga."
end

function service.Get(player: Player): Data?
    local session = sessions[player]
    if not session or session.status ~= "Loaded" or session.removeRequested or not session.data then
        return nil
    end

    return cloneData(session.data)
end

function service.Save(player: Player, deadline: number?): (boolean, string?)
    local session = sessions[player]
    if not session or session.status ~= "Loaded" or session.removeRequested or not session.data then
        return false, "No hay datos cargados correctamente para guardar."
    end

    if session.saveBlocked then
        return false, session.blockedReason or "El guardado de esta sesión está bloqueado."
    end

    if session.updating then
        return false, "Hay una transacción de datos en curso."
    end

    local store, storeError = storeProvider()
    if not store then
        return false, storeError or "No se pudo inicializar el almacén de datos."
    end

    if deadline ~= nil and (deadline ~= deadline or deadline == math.huge or deadline == -math.huge) then
        return false, "El plazo de guardado no es válido."
    end

    if session.saving then
        if deadline and (not session.saveDeadline or deadline < session.saveDeadline) then
            session.saveDeadline = deadline
        end

        local waitDeadline = os.clock() + SAVE_WAIT_TIMEOUT_SECONDS
        while session.saving do
            if session.saveDeadline then
                waitDeadline = math.min(waitDeadline, session.saveDeadline)
            end
            local remaining = waitDeadline - os.clock()
            if remaining <= 0 then
                break
            end
            task.wait(math.min(0.05, remaining))
        end

        if session.saving then
            return false, "Se agotó el tiempo de espera para el guardado en curso."
        end

        if session.saveSucceeded then
            return true, nil
        end

        return false, session.lastSaveError or "El guardado en curso falló."
    end

    if session.saveSucceeded then
        return true, nil
    end

    session.saving = true
    session.saveDeadline = deadline
    local dataToSave = PlayerData.CloneData(session.data)
    local lastError = "Error desconocido al guardar los datos."
    local blockReason: string? = nil

    for attempt = 1, MAX_ATTEMPTS do
        local activeDeadline = session.saveDeadline
        if activeDeadline and os.clock() >= activeDeadline then
            lastError = "Se agotó el plazo de cierre antes de iniciar otro intento de guardado."
            break
        end

        local callSucceeded, savedValue = pcall(function()
            return store.UpdateAsync(getKey(player), function(currentValue: unknown): Data?
                if currentValue == nil then
                    if session.baselineAbsent then
                        return cloneData(dataToSave)
                    end

                    blockReason = "El registro desapareció después de la carga; se canceló el guardado."
                    return nil
                end

                local currentData, decodeError = PlayerData.DecodeStoredData(currentValue)
                if not currentData then
                    blockReason = decodeError or "El registro actual no es válido; se canceló el guardado."
                    return nil
                end

                if PlayerData.DataEquals(currentData, dataToSave) then
                    return PlayerData.CloneData(dataToSave)
                end

                if blockReason then
                    return nil
                end

                if session.baselineAbsent
                    or not session.baseline
                    or not PlayerData.DataEquals(currentData, session.baseline)
                then
                    blockReason = "El registro cambió desde la carga; se canceló el guardado para evitar sobrescribirlo."
                    return nil
                end

                return PlayerData.CloneData(dataToSave)
            end)
        end)

        if callSucceeded then
            local confirmedData: Data? = nil
            if savedValue ~= nil then
                confirmedData = PlayerData.DecodeStoredData(savedValue)
            end

            if confirmedData and PlayerData.DataEquals(confirmedData, dataToSave) then
                session.baseline = PlayerData.CloneData(dataToSave)
                session.baselineAbsent = false
                session.saveSucceeded = true
                session.lastSaveError = nil
                break
            end
        end

        if blockReason then
            session.saveBlocked = true
            session.blockedReason = blockReason
            lastError = blockReason or "Se canceló el guardado por un conflicto."
            break
        end

        if callSucceeded then
            session.saveBlocked = true
            session.blockedReason = "UpdateAsync no confirmó datos válidos; el guardado quedó bloqueado."
            lastError = session.blockedReason or "UpdateAsync no confirmó el guardado."
            break
        end

        lastError = tostring(savedValue)
        if attempt < MAX_ATTEMPTS then
            local retryDelay = RETRY_DELAY_SECONDS * attempt
            activeDeadline = session.saveDeadline
            if activeDeadline then
                local remaining = activeDeadline - os.clock()
                if remaining <= 0 then
                    lastError = "Se agotó el plazo de cierre antes de iniciar otro intento de guardado."
                    break
                end
                task.wait(math.min(retryDelay, remaining))
            else
                task.wait(retryDelay)
            end
        end
    end

    session.saving = false
    session.saveDeadline = nil
    if not session.saveSucceeded then
        session.lastSaveError = lastError
    end

    if session.removeRequested and sessions[player] == session then
        sessions[player] = nil
    end

    if session.saveSucceeded then
        return true, nil
    end

    return false, lastError
end

function service.Update(
    player: Player,
    mutator: (Data) -> (boolean, string?)
): (boolean, Data?, string?)
    local session = sessions[player]
    if not session or session.status ~= "Loaded" or not session.data or session.removeRequested then
        return false, nil, "No hay datos cargados correctamente para modificar."
    end

    if session.saveBlocked then
        return false, nil, session.blockedReason or "Las modificaciones de esta sesión están bloqueadas."
    end

    if session.saving or session.updating then
        return false, nil, "Ya hay una operación de datos en curso."
    end

    session.updating = true
    local candidate = PlayerData.CloneData(session.data)
    local mutatorThread = coroutine.create(mutator)
    local callSucceeded, operationSucceeded, operationError = coroutine.resume(mutatorThread, candidate)
    local mutatorYielded = coroutine.status(mutatorThread) ~= "dead"
    local mutatorStopped = true
    if mutatorYielded then
        mutatorStopped = stopSuspendedMutator(mutatorThread)
    end
    session.updating = false

    if session.removeRequested or sessions[player] ~= session then
        if sessions[player] == session then
            sessions[player] = nil
        end
        return false, nil, "La sesión terminó antes de completar la transacción."
    end

    if mutatorYielded then
        if not mutatorStopped then
            session.status = "Failed"
            session.loadError = "La sesión se marcó como insegura porque no se pudo detener el mutador suspendido."
            return false, nil, "No se pudo detener de forma segura el mutador suspendido."
        end
        return false, nil, "El mutador de datos no puede ceder ejecución."
    end

    if not callSucceeded then
        return false, nil, tostring(operationSucceeded)
    end

    if not operationSucceeded then
        return false, nil, operationError or "La operación fue rechazada."
    end

    if not PlayerData.ValidateData(candidate) then
        return false, nil, "La operación produjo datos inválidos; no se aplicó ningún cambio."
    end

    session.data = PlayerData.CloneData(candidate)
    session.saveSucceeded = false
    session.lastSaveError = nil
    return true, PlayerData.CloneData(session.data), nil
end

function service.IsSaving(player: Player): boolean
    local session = sessions[player]
    return session ~= nil and session.saving
end

function service.Remove(player: Player)
    local session = sessions[player]
    if session and (session.saving or session.updating) then
        session.removeRequested = true
        return
    end

    sessions[player] = nil
end

return service
end

local productionService = createService(getProductionStore)
local PlayerDataService: PlayerDataServiceModule = {
    Load = productionService.Load,
    Get = productionService.Get,
    Save = productionService.Save,
    Update = productionService.Update,
    IsSaving = productionService.IsSaving,
    Remove = productionService.Remove,
    CreateIsolated = function(store: StoreAdapter): Service
        return createService(function(): (StoreAdapter?, string?)
            return store, nil
        end)
    end,
}

return PlayerDataService
