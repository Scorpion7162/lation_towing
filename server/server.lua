local QBCore, ESX, QBX = nil, nil, nil

local state = {
    activeTowTrucks = {},
    activeJobVehicles = {},
    towedVehicles = {},
    activeTowDrivers = {},
    jobPeds = {}
}

local function loadFramework()
    if Config.Framework == 'qbcore' then
        QBCore = exports['qb-core']:GetCoreObject()
    elseif Config.Framework == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
    elseif Config.Framework == 'qbx' then
        QBX = {}
    end
end

local function initDatabase()
    if not Config.EnableStats or not Config.PersistentStats then return end
    
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `lation_towing` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `player_identifier` VARCHAR(60) NOT NULL,
            `vehicles_towed` INT DEFAULT 0,
            `emergency_jobs` INT DEFAULT 0,
            `civilian_jobs` INT DEFAULT 0,
            `total_earned` INT DEFAULT 0,
            `distance_driven` FLOAT DEFAULT 0,
            `repairs_performed` INT DEFAULT 0,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE INDEX `player_idx` (`player_identifier`)
        )
    ]], {}, function()
        if Config.EnableServerLogs then
            print('[lation_towtruck] Database initialized')
        end
    end)
end

local function GetPlayerIdentifier(src)
    if not src then return nil end
    
    local identifier = nil
    
    if Config.Framework == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then identifier = Player.PlayerData.citizenid end
    elseif Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then identifier = xPlayer.identifier end
    elseif Config.Framework == 'qbx' then
        local Player = exports.qbx_core:GetPlayer(src)
        if Player then identifier = Player.PlayerData.citizenid end
    else
        for _, v in pairs(GetPlayerIdentifiers(src)) do
            if string.sub(v, 1, 6) == 'license' then
                identifier = v
                break
            end
        end
    end
    
    return identifier
end

local function VerifyVehicleAccess(src, netId)
    if not src or not netId then return false end
    
    if state.activeTowTrucks[netId] and state.activeTowTrucks[netId].owner == src then
        return true
    end
    
    if state.activeJobVehicles[netId] and (state.activeJobVehicles[netId].owner == src or src == state.activeJobVehicles[netId].tower) then
        return true
    end
    
    if state.towedVehicles[netId] and state.towedVehicles[netId].tower == src then
        return true
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    
    local vehicleCoords = GetEntityCoords(vehicle)
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    
    return #(vehicleCoords - playerCoords) < Config.MaxInteractionDistance
end

local function LogSecurityEvent(src, event, details)
    if not Config.EnableServerLogs then return end
    
    local playerName = GetPlayerName(src) or 'Unknown'
    local identifier = GetPlayerIdentifier(src) or 'Unknown'
    
    print(string.format('[lation_towtruck] Security Event - %s (%s) - %s - %s', 
        playerName, identifier, event, details or ''))
end

local function GivePlayerMoney(src, amount, account)
    if not src or not amount then return false end
    
    amount = math.floor(amount)
    
    if Config.Framework == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            Player.Functions.AddMoney(account or Config.PayPerDeliveryAccount, amount)
            return true
        end
    elseif Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            xPlayer.addAccountMoney(account or Config.PayPerDeliveryAccount, amount)
            return true
        end
    elseif Config.Framework == 'qbx' then
        return exports.qbx_core:AddMoney(src, account or Config.PayPerDeliveryAccount, amount)
    else
        TriggerClientEvent('lation_towtruck:receivedPayment', src, amount)
        return true
    end
    
    return false
end

local function RemovePlayerMoney(src, amount, account)
    if not src or not amount then return false end
    
    amount = math.floor(amount)
    
    if Config.Framework == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player and Player.PlayerData.money[account or Config.PayPerDeliveryAccount] >= amount then
            Player.Functions.RemoveMoney(account or Config.PayPerDeliveryAccount, amount)
            return true
        end
    elseif Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.getAccount(account or Config.PayPerDeliveryAccount).money >= amount then
            xPlayer.removeAccountMoney(account or Config.PayPerDeliveryAccount, amount)
            return true
        end
    elseif Config.Framework == 'qbx' then
        local playerMoney = exports.qbx_core:GetMoney(src, account or Config.PayPerDeliveryAccount)
        if playerMoney and playerMoney >= amount then
            return exports.qbx_core:RemoveMoney(src, account or Config.PayPerDeliveryAccount, amount)
        end
    else
        return true
    end
    
    return false
end

local function GiveVehicleKey(playerId, plate)
    if not playerId or not plate then return end
    
    if Config.Vehiclekeys == 'QBox' then
        TriggerClientEvent('vehiclekeys:client:SetOwner', playerId, plate)
    elseif Config.Vehiclekeys == 'QB' then
        TriggerClientEvent('vehiclekeys:client:SetOwner', playerId, plate)
    elseif Config.Vehiclekeys == 'Renewed' then
        exports['renzu_vehiclekeys']:givekey(playerId, plate)
    elseif Config.Vehiclekeys == 'Jaksam' then
        exports['jaksam_vehlock']:registerKey(plate, playerId)
    elseif Config.Vehiclekeys == 'Wasabi' then
        exports['wasabi_carlock']:GiveKey(plate, playerId)
    elseif Config.Vehiclekeys == 'MrNewB' then
        TriggerClientEvent('mrnewb_vehiclekeys:AddVehicleKey', playerId, plate)
    elseif Config.Vehiclekeys == 'qbx' then
        TriggerClientEvent('qbx_vehiclekeys:client:AddKeys', playerId, plate)
    elseif Config.Framework == 'esx' then
        if GetResourceState('ox_vehiclekeys') ~= 'missing' then
            exports.ox_vehiclekeys:addKey(playerId, plate)
        elseif GetResourceState('esx_vehiclelock') ~= 'missing' then
            TriggerClientEvent('esx_vehiclelock:addKeys', playerId, plate)
        end
    end
end

local function CleanupPlayerVehicles(playerId)
    if not playerId then return end
    
    for netId, data in pairs(state.activeTowTrucks) do
        if data.owner == playerId then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
            state.activeTowTrucks[netId] = nil
        end
    end
    
    for netId, data in pairs(state.activeJobVehicles) do
        if data.owner == playerId then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
            state.activeJobVehicles[netId] = nil
        end
    end
    
    for netId, data in pairs(state.towedVehicles) do
        if data.tower == playerId then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then
                DetachEntity(vehicle, true, true)
                TriggerClientEvent('lation_towtruck:vehicleTowState', -1, netId, 0, false)
                if state.activeJobVehicles[netId] then
                    DeleteEntity(vehicle)
                    state.activeJobVehicles[netId] = nil
                end
            end
            state.towedVehicles[netId] = nil
        end
    end
    
    state.activeTowDrivers[playerId] = nil
end

lib.callback.register('lation_towtruck:getPlayerStats', function(source)
    local src = source
    
    if not Config.EnableStats then 
        return {
            vehiclesTowedCount = 0,
            emergencyJobsCompleted = 0,
            civilianJobsCompleted = 0,
            totalEarned = 0,
            distanceDriven = 0,
            repairsPerformed = 0
        }
    end
    
    local identifier = GetPlayerIdentifier(src)
    if not identifier then return nil end
    
    if Config.PersistentStats then
        local result = MySQL.Sync.fetchAll('SELECT * FROM lation_towing WHERE player_identifier = ?', {identifier})
        
        if result and result[1] then
            return {
                vehiclesTowedCount = result[1].vehicles_towed,
                emergencyJobsCompleted = result[1].emergency_jobs,
                civilianJobsCompleted = result[1].civilian_jobs,
                totalEarned = result[1].total_earned,
                distanceDriven = result[1].distance_driven,
                repairsPerformed = result[1].repairs_performed
            }
        else
            MySQL.Async.execute('INSERT INTO lation_towing (player_identifier) VALUES (?)', {identifier})
            
            return {
                vehiclesTowedCount = 0,
                emergencyJobsCompleted = 0,
                civilianJobsCompleted = 0,
                totalEarned = 0,
                distanceDriven = 0,
                repairsPerformed = 0
            }
        end
    else
        return {
            vehiclesTowedCount = 0,
            emergencyJobsCompleted = 0,
            civilianJobsCompleted = 0,
            totalEarned = 0,
            distanceDriven = 0,
            repairsPerformed = 0
        }
    end
end)

lib.callback.register('lation_towtruck:spawnTowTruck', function(source)
    local src = source
    
    if state.activeTowDrivers[src] and state.activeTowDrivers[src].towTruckNetId then
        local vehicle = NetworkGetEntityFromNetworkId(state.activeTowDrivers[src].towTruckNetId)
        if DoesEntityExist(vehicle) then
            LogSecurityEvent(src, 'SpawnTowTruck', 'Attempted to spawn additional truck')
            return nil
        end
    end
    
    local spawnPos = Config.SpawnTruckLocation
    local heading = Config.SpawnTruckHeading
    
    local vehicle = CreateVehicle(Config.TowTruckModel, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, true)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    
    while not DoesEntityExist(vehicle) do Wait(10) end
    
    SetEntityDistanceCullingRadius(vehicle, 9999.0)
    SetVehicleNumberPlateText(vehicle, 'TOW' .. math.random(1000, 9999))
    SetVehicleDirtLevel(vehicle, 0)
    SetVehicleEngineOn(vehicle, true, true, false)
    
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    state.activeTowTrucks[netId] = {
        owner = src,
        timestamp = os.time()
    }
    
    if state.activeTowDrivers[src] then
        state.activeTowDrivers[src].towTruckNetId = netId
    end
    
    GiveVehicleKey(src, GetVehicleNumberPlateText(vehicle))
    
    if Config.EnableServerLogs then
        print(string.format('[lation_towtruck] Player %s spawned tow truck %s', GetPlayerName(src), netId))
    end
    
    return netId
end)

lib.callback.register('lation_towtruck:spawnJobPed', function(source)
    local src = source
    
    if not Config.SpawnStartJobNPC then return end
    
    local ped = CreatePed(4, Config.StartJobPedModel, Config.StartJobLocation.x, Config.StartJobLocation.y, Config.StartJobLocation.z, Config.StartJobPedHeading, false, true)
    if not ped or not DoesEntityExist(ped) then return nil end
    
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanPlayAmbientAnims(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    
    table.insert(state.jobPeds, ped)
    
    return NetworkGetNetworkIdFromEntity(ped)
end)

lib.callback.register('lation_towtruck:canTowVehicle', function(source, towTruckNetId, vehicleNetId)
    local src = source
    
    if not towTruckNetId or not vehicleNetId then 
        LogSecurityEvent(src, 'TowVerify', 'Missing network IDs')
        return false 
    end
    
    if not state.activeTowTrucks[towTruckNetId] or state.activeTowTrucks[towTruckNetId].owner ~= src then
        LogSecurityEvent(src, 'TowVerify', 'Not owner of tow truck')
        return false
    end
    
    local towTruck = NetworkGetEntityFromNetworkId(towTruckNetId)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    
    if not towTruck or not vehicle or not DoesEntityExist(towTruck) or not DoesEntityExist(vehicle) then
        LogSecurityEvent(src, 'TowVerify', 'Entity does not exist')
        return false
    end
    
    local towTruckCoords = GetEntityCoords(towTruck)
    local vehicleCoords = GetEntityCoords(vehicle)
    
    if #(towTruckCoords - vehicleCoords) > Config.TowingRange then
        LogSecurityEvent(src, 'TowVerify', 'Vehicle too far from tow truck')
        return false
    end
    
    for _, data in pairs(state.towedVehicles) do
        if data.vehicleNetId == vehicleNetId then
            LogSecurityEvent(src, 'TowVerify', 'Vehicle already being towed')
            return false
        end
    end
    
    return true
end)

lib.callback.register('lation_towtruck:canDetachVehicle', function(source, vehicleNetId)
    local src = source
    
    if not vehicleNetId then 
        LogSecurityEvent(src, 'DetachVerify', 'Missing network ID')
        return false 
    end
    
    if not state.towedVehicles[vehicleNetId] or state.towedVehicles[vehicleNetId].tower ~= src then
        LogSecurityEvent(src, 'DetachVerify', 'Not tower of vehicle')
        return false
    end
    
    return true
end)

lib.callback.register('lation_towtruck:checkJob', function(source)
    local src = source
    
    if not Config.RequireJob then return true end
    
    local hasJob = false
    
    if Config.Framework == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            hasJob = Player.PlayerData.job.name == Config.JobName
        end
    elseif Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            hasJob = xPlayer.job.name == Config.JobName
        end
    elseif Config.Framework == 'qbx' then
        hasJob = exports.qbx_core:HasPrimaryGroup(src, Config.JobName)
    end
    
    return hasJob
end)
lib.callback.register('lation_towtruck:checkTowTruck', function(source, netId)
    return state.activeTowTrucks[netId] ~= nil
end)

lib.callback.register('lation_towtruck:clockIn', function(source)
    local src = source
    
    if state.activeTowDrivers[src] and state.activeTowDrivers[src].onDuty then
        LogSecurityEvent(src, 'ClockIn', 'Already clocked in')
        return false
    end
    
    state.activeTowDrivers[src] = state.activeTowDrivers[src] or {}
    state.activeTowDrivers[src].onDuty = true
    state.activeTowDrivers[src].timestamp = os.time()
    state.activeTowDrivers[src].lastJob = 0
    
    return true
end)

lib.callback.register('lation_towtruck:clockOut', function(source)
    local src = source
    
    if not state.activeTowDrivers[src] or not state.activeTowDrivers[src].onDuty then
        LogSecurityEvent(src, 'ClockOut', 'Not clocked in')
        return false
    end
    
    state.activeTowDrivers[src].onDuty = false
    
    for netId, data in pairs(state.activeJobVehicles) do
        if data.owner == src then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
            state.activeJobVehicles[netId] = nil
        end
    end
    
    return true
end)

lib.callback.register('lation_towtruck:repairVehicle', function(source, vehicleNetId, cost)
    local src = source
    
    if not VerifyVehicleAccess(src, vehicleNetId) then
        LogSecurityEvent(src, 'RepairVehicle', 'No access to vehicle')
        return false
    end
    
    if not RemovePlayerMoney(src, cost) then
        return false
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    
    if DoesEntityExist(vehicle) then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleUndriveable(vehicle, false)
    end
    
    return true
end)

lib.callback.register('lation_towtruck:maintainVehicle', function(source, vehicleNetId, cost)
    local src = source
    
    if not VerifyVehicleAccess(src, vehicleNetId) then
        LogSecurityEvent(src, 'MaintainVehicle', 'No access to vehicle')
        return false
    end
    
    if not RemovePlayerMoney(src, cost) then
        return false
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    
    if DoesEntityExist(vehicle) then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleFuelLevel(vehicle, 100.0)
        SetVehicleOilLevel(vehicle, 1000.0)
        SetVehicleEngineHealth(vehicle, 1000.0)
    end
    
    return true
end)

lib.callback.register('lation_towtruck:deliverVehicle', function(source, vehicleNetId, isEmergency)
    local src = source
    
    if not state.towedVehicles[vehicleNetId] or state.towedVehicles[vehicleNetId].tower ~= src then
        LogSecurityEvent(src, 'DeliverVehicle', 'Not tower of vehicle')
        return false
    end
    
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    if #(playerCoords - vector3(Config.DeliverLocation.x, Config.DeliverLocation.y, Config.DeliverLocation.z)) > Config.DeliverRadius then
        LogSecurityEvent(src, 'DeliverVehicle', 'Not in delivery area')
        return false
    end
    
    local amount
    
    if Config.RandomPayPerDelivery then
        amount = isEmergency and 
            math.random(Config.MinPayPerDelivery, Config.MaxPayPerDelivery) * Config.EmergencyPayMultiplier or
            math.random(Config.MinPayPerDelivery, Config.MaxPayPerDelivery)
    else
        amount = isEmergency and
            Config.PayPerDelivery * Config.EmergencyPayMultiplier or
            Config.PayPerDelivery
    end
    
    amount = math.floor(amount)
    
    if not GivePlayerMoney(src, amount) then
        return false
    end
    
    return amount
end)

lib.callback.register('lation_towtruck:cleanupDelivery', function(source, vehicleNetId)
    local src = source
    
    if not state.towedVehicles[vehicleNetId] or state.towedVehicles[vehicleNetId].tower ~= src then
        LogSecurityEvent(src, 'CleanupDelivery', 'Not tower of vehicle')
        return false
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    
    if DoesEntityExist(vehicle) then
        for towTruckNetId, data in pairs(state.activeTowTrucks) do
            local towTruck = NetworkGetEntityFromNetworkId(towTruckNetId)
            if DoesEntityExist(towTruck) then
                DetachEntity(vehicle, true, true)
            end
        end
        
        state.towedVehicles[vehicleNetId] = nil
        state.activeJobVehicles[vehicleNetId] = nil
        
        TriggerClientEvent('lation_towtruck:vehicleTowState', -1, vehicleNetId, 0, false)
        
        lib.setTimeout(500, function()
            if DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
        end)
    end
    
    return true
end)

RegisterNetEvent('lation_towtruck:startTowing', function(towTruckNetId, vehicleNetId)
    local src = source
    
    if not towTruckNetId or not vehicleNetId then
        LogSecurityEvent(src, 'StartTowing', 'Missing network IDs')
        return
    end
    
    if not state.activeTowTrucks[towTruckNetId] or state.activeTowTrucks[towTruckNetId].owner ~= src then
        LogSecurityEvent(src, 'StartTowing', 'Not owner of tow truck')
        return
    end
    
    local towTruck = NetworkGetEntityFromNetworkId(towTruckNetId)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    
    if not towTruck or not vehicle or not DoesEntityExist(towTruck) or not DoesEntityExist(vehicle) then
        LogSecurityEvent(src, 'StartTowing', 'Entity does not exist')
        return
    end
    
    local towTruckCoords = GetEntityCoords(towTruck)
    local vehicleCoords = GetEntityCoords(vehicle)
    
    if #(towTruckCoords - vehicleCoords) > Config.TowingRange then
        LogSecurityEvent(src, 'StartTowing', 'Vehicle too far from tow truck')
        return
    end
    
    local attachBone = Config.AttachBone
    local xOffset = Config.TowOffset.x
    local yOffset = Config.TowOffset.y
    local zOffset = Config.TowOffset.z
    local xRot = Config.TowRotation.x
    local yRot = Config.TowRotation.y
    local zRot = Config.TowRotation.z
    
    for existingNetId, data in pairs(state.towedVehicles) do
        if data.tower == src then
            local existingVehicle = NetworkGetEntityFromNetworkId(existingNetId)
            if DoesEntityExist(existingVehicle) then
                DetachEntity(existingVehicle, true, true)
                TriggerClientEvent('lation_towtruck:vehicleTowState', -1, existingNetId, 0, false)
            end
            state.towedVehicles[existingNetId] = nil
        end
    end
    
    AttachEntityToEntity(vehicle, towTruck, attachBone, xOffset, yOffset, zOffset, xRot, yRot, zRot, false, false, false, false, 20, true)
    
    state.towedVehicles[vehicleNetId] = {
        tower = src,
        towTruckNetId = towTruckNetId,
        vehicleNetId = vehicleNetId,
        timestamp = os.time()
    }
    
    if state.activeJobVehicles[vehicleNetId] then
        state.activeJobVehicles[vehicleNetId].tower = src
    end
    
    TriggerClientEvent('lation_towtruck:vehicleTowState', -1, vehicleNetId, towTruckNetId, true)
    
    if Config.EnableServerLogs then
        print(string.format('[lation_towtruck] Player %s started towing vehicle %s', GetPlayerName(src), vehicleNetId))
    end
end)

RegisterNetEvent('lation_towtruck:stopTowing', function(vehicleNetId)
    local src = source
    
    if not vehicleNetId then
        LogSecurityEvent(src, 'StopTowing', 'Missing network ID')
        return
    end
    
    if not state.towedVehicles[vehicleNetId] or state.towedVehicles[vehicleNetId].tower ~= src then
        LogSecurityEvent(src, 'StopTowing', 'Not tower of vehicle')
        return
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    
    if DoesEntityExist(vehicle) then
        DetachEntity(vehicle, true, true)
        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
        
        local coords = GetEntityCoords(vehicle)
        SetEntityCoords(vehicle, coords.x, coords.y, coords.z + 0.5, false, false, false, false)
        
        local plate = GetVehicleNumberPlateText(vehicle):trim()
        GiveVehicleKey(src, plate)
    end
    
    TriggerClientEvent('lation_towtruck:vehicleTowState', -1, vehicleNetId, 0, false)
    
    if state.activeJobVehicles[vehicleNetId] then
        state.activeJobVehicles[vehicleNetId].tower = nil
    end
    
    state.towedVehicles[vehicleNetId] = nil
    
    if Config.EnableServerLogs then
        print(string.format('[lation_towtruck] Player %s stopped towing vehicle %s', GetPlayerName(src), vehicleNetId))
    end
end)

RegisterNetEvent('lation_towtruck:requestJob', function(isEmergency)
    local src = source
    
    if not state.activeTowDrivers[src] or not state.activeTowDrivers[src].onDuty then
        LogSecurityEvent(src, 'RequestJob', 'Not on duty')
        return
    end
    
    local currentTime = os.time()
    local lastJobTime = state.activeTowDrivers[src].lastJob or 0
    local cooldownTime = isEmergency and Config.EmergencyCooldown/1000 or Config.JobCooldown/1000
    
    if currentTime - lastJobTime < cooldownTime then
        LogSecurityEvent(src, 'RequestJob', 'Cooldown active')
        return
    end
    
    state.activeTowDrivers[src].lastJob = currentTime
    
    local selectedLocation
    
    if isEmergency then
        selectedLocation = Config.EmergencyLocations[math.random(#Config.EmergencyLocations)]
    else
        local location = Config.Locations[math.random(#Config.Locations)]
        selectedLocation = vector4(location.x, location.y, location.z, location.h)
    end
    
    local vehicleModel = Config.CarModels[math.random(#Config.CarModels)]
    local vehicle = CreateVehicle(vehicleModel, selectedLocation.x, selectedLocation.y, selectedLocation.z, selectedLocation.w, true, true)
    
    if not vehicle or not DoesEntityExist(vehicle) then
        LogSecurityEvent(src, 'RequestJob', 'Failed to spawn vehicle')
        return
    end
    
    while not DoesEntityExist(vehicle) do Wait(10) end
    
    SetEntityDistanceCullingRadius(vehicle, 9999.0)
    SetEntityAsMissionEntity(vehicle, true, true)
    
    local health = math.random(Config.MinVehicleHealth, Config.MaxVehicleHealth)
    SetVehicleBodyHealth(vehicle, health)
    SetVehicleEngineHealth(vehicle, health)
    
    if Config.DisableVehicleEngines then
        SetVehicleEngineOn(vehicle, false, false, true)
    end
    
if isEmergency and Config.EmergencyEffects then
        SetVehicleLights(vehicle, 2)
        SetVehicleAlarm(vehicle, true)
        StartVehicleAlarm(vehicle)
    end
    
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    
    state.activeJobVehicles[netId] = {
        owner = src,
        timestamp = os.time(),
        isEmergency = isEmergency,
        tower = nil
    }
    
    TriggerClientEvent('lation_towtruck:assignJob', src, vector3(selectedLocation.x, selectedLocation.y, selectedLocation.z), isEmergency, netId)
    
    if Config.EnableServerLogs then
        print(string.format('[lation_towtruck] Assigned %s job to player %s', isEmergency and 'emergency' or 'regular', GetPlayerName(src)))
    end
end)

RegisterNetEvent('lation_towtruck:abandonJob', function()
    local src = source
    
    for netId, data in pairs(state.activeJobVehicles) do
        if data.owner == src and not data.tower then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
            state.activeJobVehicles[netId] = nil
            
            if Config.EnableServerLogs then
                print(string.format('[lation_towtruck] Player %s abandoned job vehicle %s', GetPlayerName(src), netId))
            end
        end
    end
end)

RegisterNetEvent('lation_towtruck:deleteTowTruck', function(netId)
    local src = source
    
    if not state.activeTowTrucks[netId] or state.activeTowTrucks[netId].owner ~= src then
        LogSecurityEvent(src, 'DeleteTowTruck', 'Not owner of vehicle')
        return
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end
    
    state.activeTowTrucks[netId] = nil
    
    if state.activeTowDrivers[src] then
        state.activeTowDrivers[src].towTruckNetId = nil
    end
    
    if Config.EnableServerLogs then
        print(string.format('[lation_towtruck] Player %s deleted tow truck %s', GetPlayerName(src), netId))
    end
end)

RegisterNetEvent('lation_towtruck:saveStats', function(stats)
    local src = source
    
    if not Config.EnableStats then return end
    
    local identifier = GetPlayerIdentifier(src)
    if not identifier then return end
    
    if Config.PersistentStats then
        MySQL.Async.execute('UPDATE lation_towing SET vehicles_towed = ?, emergency_jobs = ?, civilian_jobs = ?, total_earned = ?, distance_driven = ?, repairs_performed = ? WHERE player_identifier = ?', {
            stats.vehiclesTowedCount,
            stats.emergencyJobsCompleted,
            stats.civilianJobsCompleted,
            stats.totalEarned,
            stats.distanceDriven,
            stats.repairsPerformed,
            identifier
        })
    end
end)

RegisterNetEvent('lation_towtruck:updateDistance', function(distance)
    local src = source
    
    if not Config.EnableStats or not distance then return end
    
    local identifier = GetPlayerIdentifier(src)
    if not identifier then return end
    
    if Config.PersistentStats then
        MySQL.Async.execute('UPDATE lation_towing SET distance_driven = ? WHERE player_identifier = ?', {
            distance,
            identifier
        })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    
    for netId, data in pairs(state.activeJobVehicles) do
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    end
    
    for netId, data in pairs(state.activeTowTrucks) do
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    end
    
    for _, ped in ipairs(state.jobPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    CleanupPlayerVehicles(src)
end)

CreateThread(function()
    while true do
        Wait(60000) 
        
        local currentTime = os.time()
        
        for netId, data in pairs(state.activeTowTrucks) do
            local playerId = data.owner
            
            if not GetPlayerName(playerId) or currentTime - data.timestamp > Config.VehicleCleanupTime then
                local vehicle = NetworkGetEntityFromNetworkId(netId)
                
                if DoesEntityExist(vehicle) and not IsPedInVehicle(GetPlayerPed(playerId), vehicle, false) then
                    DeleteEntity(vehicle)
                    state.activeTowTrucks[netId] = nil
                    
                    if Config.EnableServerLogs then
                        print(string.format('[lation_towtruck] Cleaned up abandoned tow truck %s', netId))
                    end
                end
            end
        end
        
        for netId, data in pairs(state.activeJobVehicles) do
            if currentTime - data.timestamp > Config.JobVehicleTimeout then
                local vehicle = NetworkGetEntityFromNetworkId(netId)
                
                if DoesEntityExist(vehicle) then
                    if state.towedVehicles[netId] then
                        local towTruckNetId = state.towedVehicles[netId].towTruckNetId
                        local towTruck = NetworkGetEntityFromNetworkId(towTruckNetId)
                        
                        if DoesEntityExist(towTruck) then
                            DetachEntity(vehicle, true, true)
                        end
                        
                        state.towedVehicles[netId] = nil
                        TriggerClientEvent('lation_towtruck:vehicleTowState', -1, netId, 0, false)
                    end
                    
                    DeleteEntity(vehicle)
                end
                
                state.activeJobVehicles[netId] = nil
                
                if Config.EnableServerLogs then
                    print(string.format('[lation_towtruck] Cleaned up abandoned job vehicle %s', netId))
                end
            end
        end
        
        for netId, data in pairs(state.towedVehicles) do
            if currentTime - data.timestamp > Config.TowedVehicleTimeout then
                local vehicle = NetworkGetEntityFromNetworkId(netId)
                
                if DoesEntityExist(vehicle) then
                    DetachEntity(vehicle, true, true)
                    TriggerClientEvent('lation_towtruck:vehicleTowState', -1, netId, 0, false)
                end
                
                state.towedVehicles[netId] = nil
                
                if Config.EnableServerLogs then
                    print(string.format('[lation_towtruck] Cleaned up stale towed vehicle reference %s', netId))
                end
            end
        end
    end
end)

CreateThread(function()
    loadFramework()
    initDatabase()
    
    if Config.EnableServerLogs then
        print('[lation_towtruck] Server initialized')
    end
end)