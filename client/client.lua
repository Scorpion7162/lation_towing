local QBCore, ESX, QBX = nil, nil, nil
local PlayerJob = {}
local state = {
    isTowing = false,
    towingVehicle = nil,
    targetVehicle = nil,
    towBlip = nil,
    deliveryBlip = nil,
    emergencyBlip = nil,
    onDuty = false,
    jobCooldown = false,
    distanceAccumulator = 0,
    lastUpdateTime = 0,
    jobActive = false,
    lastJobTime = 0,
    isEmergencyJob = false,
    radioActive = false,
    jobZone = nil,
    deliveryZone = nil,
    lastCoords = nil,
    animDicts = {}
}

local playerStats = {
    vehiclesTowedCount = 0,
    emergencyJobsCompleted = 0,
    civilianJobsCompleted = 0,
    totalEarned = 0,
    distanceDriven = 0,
    repairsPerformed = 0
}
local function loadFramework()
    if Config.Framework == 'qbcore' then
        QBCore = exports['qb-core']:GetCoreObject()
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            PlayerJob = QBCore.Functions.GetPlayerData().job
            if Config.EnableStats then
                FetchPlayerStats()
            end
        end)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
            PlayerJob = JobInfo
        end)
    elseif Config.Framework == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
        RegisterNetEvent('esx:playerLoaded', function(xPlayer)
            PlayerJob = xPlayer.job
            if Config.EnableStats then
                FetchPlayerStats()
            end
        end)
        RegisterNetEvent('esx:setJob', function(job)
            PlayerJob = job
        end)
    elseif Config.Framework == 'qbx' then
        QBX = exports.qbx_core
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            local playerData = QBX:GetPlayerData()
            PlayerJob = playerData.job
            if Config.EnableStats then
                FetchPlayerStats()
            end
        end)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
            PlayerJob = JobInfo
        end)
    end
end

local function FetchPlayerStats()
    if not Config.EnableStats then return end
    local stats = lib.callback.await('lation_towtruck:getPlayerStats', false)
    if stats then
        playerStats = stats
    end
end

local function showNotification(message, type)
    lib.notify({
        title = Notifications.title,
        description = message,
        icon = Notifications.icon,
        position = Notifications.position,
        type = type or 'info'
    })
end

local function hasRequiredJob()
    if not Config.RequireJob then return true end
    
    if Config.Framework == 'qbx' then
        return QBX:HasPrimaryGroup(Config.JobName)
    else
        return lib.callback.await('lation_towtruck:checkJob', false)
    end
end

local function createBlip(coords, sprite, color, text, scale, route)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, scale)
    SetBlipColour(blip, color)
    SetBlipAsShortRange(blip, not route)
    if route then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, color)
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(text)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function removeBlip(blip)
    if blip and DoesBlipExist(blip) then
        SetBlipRoute(blip, false)
        RemoveBlip(blip)
        return nil
    end
    return blip
end

local function playAnimation(dict, anim, duration)
    if not dict or not anim or not duration then return false end
    
    if not state.animDicts[dict] then
        local success = lib.requestAnimDict(dict, 1000)
        if not success then
            showNotification('Failed to load animation', 'error')
            return false
        end
        state.animDicts[dict] = true
    end
    
    TaskPlayAnim(cache.ped, dict, anim, 8.0, -8.0, duration, 49, 0, false, false, false)
    lib.setTimeout(duration, function()
        if IsEntityPlayingAnim(cache.ped, dict, anim, 3) then
            ClearPedTasks(cache.ped)
        end
    end)
    return true
end

local function toggleRadio(status)
    state.radioActive = status
    if Config.UseInteractSound and state.radioActive then
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'towradio', 0.1)
    end
    showNotification(state.radioActive and 'Tow dispatch radio activated' or 'Tow dispatch radio deactivated', state.radioActive and 'success' or 'error')
end

local function attachVehicle(towTruck, vehicle)
    if not towTruck or not vehicle or not IsEntityAVehicle(towTruck) or not IsEntityAVehicle(vehicle) then
        showNotification('Invalid vehicles for towing', 'error')
        return false
    end
    
    local canTow = lib.callback.await('lation_towtruck:canTowVehicle', false, NetworkGetNetworkIdFromEntity(towTruck), NetworkGetNetworkIdFromEntity(vehicle))
    if not canTow then
        showNotification('You cannot tow this vehicle', 'error')
        return false
    end
    
    local towModel = GetEntityModel(towTruck)
    if towModel ~= Config.TowTruckModel then
        showNotification('This is not a valid tow truck', 'error')
        return false
    end
    
    if not playAnimation(Config.AnimDict, Config.AnimName, Config.AttachAnimationDuration) then
        return false
    end
    
    TriggerServerEvent('lation_towtruck:startTowing', 
        NetworkGetNetworkIdFromEntity(towTruck), 
        NetworkGetNetworkIdFromEntity(vehicle)
    )
    
    state.targetVehicle = vehicle
    state.isTowing = true
    showNotification(Notifications.successfulVehicleLoad, 'success')
    return true
end

local function detachVehicle()
    if not state.isTowing or not state.targetVehicle then
        showNotification(Notifications.noVehicleToUnload, 'error')
        return false
    end
    
    local canDetach = lib.callback.await('lation_towtruck:canDetachVehicle', false, NetworkGetNetworkIdFromEntity(state.targetVehicle))
    if not canDetach then
        showNotification('You cannot detach this vehicle', 'error')
        return false
    end
    
    if not playAnimation(Config.AnimDict, Config.AnimName, Config.DetachAnimationDuration) then
        return false
    end
    
    local vehNetId = NetworkGetNetworkIdFromEntity(state.targetVehicle)
    TriggerServerEvent('lation_towtruck:stopTowing', vehNetId)
    state.targetVehicle = nil
    state.isTowing = false
    showNotification(Notifications.sucessfulVehicleUnload, 'success')
    return true
end

local function deliverVehicle()
    if not state.isTowing or not state.targetVehicle then
        showNotification(Notifications.noVehicleToUnload, 'error')
        return false
    end
    
    if not playAnimation(Config.AnimDict, Config.AnimName, Config.DeliverAnimationDuration) then
        return false
    end
    
    local vehNetId = NetworkGetNetworkIdFromEntity(state.targetVehicle)
    local payment = lib.callback.await('lation_towtruck:deliverVehicle', false, vehNetId, state.isEmergencyJob)
    
    if payment then
        showNotification('You received $' .. payment .. ' for the delivery', 'success')
        
        if lib.callback.await('lation_towtruck:cleanupDelivery', false, vehNetId) then
            state.targetVehicle = nil
            state.isTowing = false
            state.isEmergencyJob = false
            state.jobActive = false
            
            state.towBlip = removeBlip(state.towBlip)
            state.deliveryBlip = removeBlip(state.deliveryBlip)
            state.emergencyBlip = removeBlip(state.emergencyBlip)
            
            if state.lastCoords then
                local jobDistance = #(cache.coords - state.lastCoords)
                playerStats.distanceDriven = playerStats.distanceDriven + jobDistance
            end
            
            if Config.EnableStats then
                playerStats.vehiclesTowedCount = playerStats.vehiclesTowedCount + 1
                playerStats.totalEarned = playerStats.totalEarned + payment
                
                if state.isEmergencyJob then
                    playerStats.emergencyJobsCompleted = playerStats.emergencyJobsCompleted + 1
                else
                    playerStats.civilianJobsCompleted = playerStats.civilianJobsCompleted + 1
                end
                
                TriggerServerEvent('lation_towtruck:saveStats', playerStats)
            end
            
            if Config.UseJobUI and state.onDuty then
                CreateJobDialog()
            end
            
            return true
        end
    end
    
    showNotification('Failed to process delivery', 'error')
    return false
end

local function repairVehicle()
    if not state.targetVehicle then
        showNotification('No vehicle to repair', 'error')
        return false
    end
    
    local vehNetId = NetworkGetNetworkIdFromEntity(state.targetVehicle)
    local success = lib.callback.await('lation_towtruck:repairVehicle', false, vehNetId, Config.RepairCost)
    
    if success then
        if not playAnimation(Config.AnimDict, Config.AnimName, Config.RepairDuration) then
            return false
        end
        
        if Config.EnableStats then
            playerStats.repairsPerformed = playerStats.repairsPerformed + 1
            TriggerServerEvent('lation_towtruck:saveStats', playerStats)
        end
        
        showNotification('Vehicle repaired for $' .. Config.RepairCost, 'success')
        return true
    end
    
    showNotification('You cannot afford the repair cost of $' .. Config.RepairCost, 'error')
    return false
end

local function maintainTruck()
    if not state.towingVehicle then
        showNotification('No tow truck to maintain', 'error')
        return false
    end
    
    local vehNetId = NetworkGetNetworkIdFromEntity(state.towingVehicle)
    local success = lib.callback.await('lation_towtruck:maintainVehicle', false, vehNetId, Config.MaintenanceCost)
    
    if success then
        if not playAnimation(Config.AnimDict, Config.AnimName, Config.MaintenanceDuration) then
            return false
        end
        
        showNotification('Truck maintained for $' .. Config.MaintenanceCost, 'success')
        return true
    end
    
    showNotification('You cannot afford the maintenance cost of $' .. Config.MaintenanceCost, 'error')
    return false
end

local function spawnTowTruck()
    local isJobAuthorized = hasRequiredJob()
    if not isJobAuthorized then
        showNotification(Notifications.notAuthorized, 'error')
        return nil
    end
    
    local result = lib.callback.await('lation_towtruck:spawnTowTruck', false)
    if not result then
        showNotification('Failed to spawn tow truck', 'error')
        return nil
    end
    
    state.towingVehicle = NetworkGetEntityFromNetworkId(result)
    if not state.towingVehicle or not DoesEntityExist(state.towingVehicle) then
        showNotification('Error retrieving spawned vehicle', 'error')
        return nil
    end
    
    return state.towingVehicle
end

local function clockIn()
    local isJobAuthorized = hasRequiredJob()
    if not isJobAuthorized then
        showNotification(Notifications.notAuthorized, 'error')
        return false
    end
    
    if not lib.callback.await('lation_towtruck:clockIn', false) then
        showNotification('Failed to clock in', 'error')
        return false
    end
    
    state.onDuty = true
    showNotification(Notifications.clockedIn, 'success')
    
    if Config.AutoAssignJobs then
        lib.setTimeout(math.random(Config.MinWaitTime * 60000, Config.MaxWaitTime * 60000), function()
            if state.onDuty and not state.jobActive then
                TriggerServerEvent('lation_towtruck:requestJob', false)
            end
        end)
    end
    
    return true
end

local function clockOut()
    if not lib.callback.await('lation_towtruck:clockOut', false) then
        showNotification('Failed to clock out', 'error')
        return false
    end
    
    state.onDuty = false
    state.isEmergencyJob = false
    state.jobActive = false
    
    state.towBlip = removeBlip(state.towBlip)
    state.deliveryBlip = removeBlip(state.deliveryBlip)
    state.emergencyBlip = removeBlip(state.emergencyBlip)
    
    if state.towingVehicle and DoesEntityExist(state.towingVehicle) then
        if cache.seat == -1 and cache.vehicle == state.towingVehicle then
            TaskLeaveVehicle(cache.ped, state.towingVehicle, 0)
            Wait(1500)
        end
        
        TriggerServerEvent('lation_towtruck:deleteTowTruck', NetworkGetNetworkIdFromEntity(state.towingVehicle))
        state.towingVehicle = nil
    end
    
    showNotification('You\'ve clocked out and returned your tow truck', 'error')
    return true
end

local function CreateTowMenu()
    lib.registerContext({
        id = 'tow_main_menu',
        title = ContextMenu.menuTitle,
        options = {
            {
                title = ContextMenu.towTruckTitle,
                description = ContextMenu.towTruckDescription,
                icon = ContextMenu.towTruckIcon,
                onSelect = function()
                    spawnTowTruck()
                    if Config.AutoClockIn then
                        clockIn()
                    end
                end
            },
            {
                title = ContextMenu.clockInTitle,
                description = state.onDuty and ContextMenu.clockInDescription2 or ContextMenu.clockInDescription,
                icon = ContextMenu.clockInIcon,
                disabled = state.onDuty,
                onSelect = function()
                    if not state.onDuty then
                        clockIn()
                    end
                end
            },
            {
                title = ContextMenu.clockOutTitle,
                description = state.onDuty and ContextMenu.clockOutDescription or ContextMenu.clockOutDescription2,
                icon = ContextMenu.clockOutIcon,
                disabled = not state.onDuty,
                onSelect = function()
                    if state.onDuty then
                        clockOut()
                    end
                end
            },
            {
                title = 'View Stats',
                description = 'See your towing statistics',
                icon = 'chart-line',
                disabled = not Config.EnableStats,
                onSelect = function()
                    if not Config.EnableStats then return end
                    lib.registerContext({
                        id = 'towing_stats',
                        title = 'Towing Statistics',
                        options = {
                            {
                                title = 'Vehicles Towed: ' .. playerStats.vehiclesTowedCount,
                                disabled = true
                            },
                            {
                                title = 'Emergency Jobs: ' .. playerStats.emergencyJobsCompleted,
                                disabled = true
                            },
                            {
                                title = 'Civilian Jobs: ' .. playerStats.civilianJobsCompleted,
                                disabled = true
                            },
                            {
                                title = 'Total Earned: $' .. playerStats.totalEarned,
                                disabled = true
                            },
                            {
                                title = 'Distance Driven: ' .. math.floor(playerStats.distanceDriven) .. ' m',
                                disabled = true
                            },
                            {
                                title = 'Repairs Performed: ' .. playerStats.repairsPerformed,
                                disabled = true
                            }
                        }
                    })
                    lib.showContext('towing_stats')
                end
            }
        }
    })
    lib.showContext('tow_main_menu')
end

local function CreateJobDialog()
    lib.registerContext({
        id = 'tow_job_continuation',
        title = 'Towing Job',
        options = {
            {
                title = 'Accept New Job',
                description = 'Continue working and get a new job',
                icon = 'check',
                onSelect = function()
                    showNotification(Notifications.confirmNextJob, 'success')
                    lib.setTimeout(math.random(Config.MinWaitTime * 60000, Config.MaxWaitTime * 60000), function()
                        if state.onDuty and not state.jobActive then
                            TriggerServerEvent('lation_towtruck:requestJob', false)
                        end
                    end)
                end
            },
            {
                title = 'End Work',
                description = 'Stop working and clock out',
                icon = 'times',
                onSelect = function()
                    clockOut()
                end
            }
        }
    })
    lib.showContext('tow_job_continuation')
end

local function SetupTargetSystem()
    if GetResourceState('ox_target') ~= 'started' then return end
    
    exports.ox_target:addGlobalVehicle({
        {
            name = 'tow_attach_vehicle',
            icon = Target.loadVehicleIcon,
            label = Target.loadVehicle,
            distance = Target.distance,
            canInteract = function(entity, distance, coords, name)
                if not hasRequiredJob() or
                   not state.towingVehicle or 
                   not DoesEntityExist(state.towingVehicle) or
                   cache.vehicle or
                   state.isTowing or
                   entity == state.towingVehicle then 
                    return false 
                end
                
                local towPos = GetEntityCoords(state.towingVehicle)
                local entityPos = GetEntityCoords(entity)
                return #(towPos - entityPos) <= Config.TowingRange
            end,
            onSelect = function(data)
                attachVehicle(state.towingVehicle, data.entity)
            end
        }
    })
    
    exports.ox_target:addModel(Config.TowTruckModel, {
        {
            name = 'tow_detach_vehicle',
            icon = Target.unloadVehicleIcon,
            label = Target.unloadVehicle,
            distance = Target.distance,
            canInteract = function(entity, distance, coords, name)
                return hasRequiredJob() and
                       not cache.vehicle and
                       state.isTowing and 
                       entity == state.towingVehicle
            end,
            onSelect = function(data)
                detachVehicle()
            end
        },
        {
            name = 'tow_repair_vehicle',
            icon = 'wrench',
            label = 'Repair Vehicle',
            distance = Target.distance,
            canInteract = function(entity, distance, coords, name)
                return hasRequiredJob() and
                       not cache.vehicle and
                       state.isTowing and 
                       entity == state.towingVehicle
            end,
            onSelect = function(data)
                repairVehicle()
            end
        },
        {
            name = 'tow_maintain_truck',
            icon = 'oil-can',
            label = 'Maintain Truck',
            distance = Target.distance,
            canInteract = function(entity, distance, coords, name)
                return hasRequiredJob() and
                       not cache.vehicle and
                       entity == state.towingVehicle
            end,
            onSelect = function(data)
                maintainTruck()
            end
        }
    })
    
    if Config.SpawnStartJobNPC then
        exports.ox_target:addModel(Config.StartJobPedModel, {
            {
                name = 'tow_job_start',
                icon = Target.startJobIcon,
                label = Target.startJob,
                distance = Target.distance,
                canInteract = function()
                    return hasRequiredJob()
                end,
                onSelect = function()
                    CreateTowMenu()
                end
            }
        })
    end
end

local function SetupZones()
    if state.jobZone then
        state.jobZone:remove()
        state.jobZone = nil
    end
    
    if state.deliveryZone then
        state.deliveryZone:remove()
        state.deliveryZone = nil
    end
    
    state.jobZone = lib.zones.sphere({
        coords = Config.StartJobLocation,
        radius = 3.0,
        debug = false,
        onEnter = function()
            if hasRequiredJob() then
                lib.showTextUI('[E] Access Tow Job', {position = 'top-center'})
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end
    })
    
    state.deliveryZone = lib.zones.sphere({
        coords = Config.DeliverLocation,
        radius = Config.DeliverRadius,
        debug = false,
        onEnter = function()
            if state.isTowing and state.targetVehicle and cache.vehicle == state.towingVehicle and cache.seat == -1 then
                lib.showTextUI('[E] Deliver Vehicle', {position = 'top-center'})
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end
    })
end

local function TrackDistance()
    if Config.EnableStats and state.onDuty and state.towingVehicle and DoesEntityExist(state.towingVehicle) then
        if cache.vehicle == state.towingVehicle and cache.seat == -1 then
            if state.lastCoords then
                local distance = #(cache.coords - state.lastCoords)
                if distance > 5.0 then
                    state.distanceAccumulator = state.distanceAccumulator + distance
                    state.lastCoords = cache.coords
                    playerStats.distanceDriven = playerStats.distanceDriven + distance
                    
                    local currentTime = GetGameTimer()
                    if state.distanceAccumulator > 200.0 or (currentTime - state.lastUpdateTime) > 60000 then
                        TriggerServerEvent('lation_towtruck:updateDistance', playerStats.distanceDriven)
                        state.distanceAccumulator = 0
                        state.lastUpdateTime = currentTime
                    end
                end
            else
                state.lastCoords = cache.coords
            end
        end
    end
end

local function HandleKeypress()
    if IsControlJustPressed(0, 38) then
        if state.isTowing and state.targetVehicle and #(cache.coords - Config.DeliverLocation) < Config.DeliverRadius and cache.vehicle == state.towingVehicle and cache.seat == -1 then
            deliverVehicle()
        end
        
        if hasRequiredJob() and #(cache.coords - Config.StartJobLocation) < 3.0 and not cache.vehicle then
            CreateTowMenu()
        end
    end
end

local function InitializeTowingSystem()
    local blipData = Config.Blips.startJob
    local startBlip = createBlip(Config.StartJobLocation, blipData.blipSprite, blipData.blipColor, blipData.blipName, blipData.blipScale, false)
    
    SetupTargetSystem()
    SetupZones()
    
    if Config.SpawnStartJobNPC then
        lib.callback.await('lation_towtruck:spawnJobPed', false)
    end
    
    RegisterCommand(Config.DispatchCommand, function()
        if hasRequiredJob() and state.onDuty and not state.jobActive then
            TriggerServerEvent('lation_towtruck:requestJob', false)
        end
    end, false)
    
    RegisterCommand('towemergency', function()
        if hasRequiredJob() and state.onDuty and not state.jobActive then
            TriggerServerEvent('lation_towtruck:requestJob', true)
        end
    end, false)
    
    RegisterCommand(Config.JobMenuCommand, function()
        if hasRequiredJob() then
            CreateTowMenu()
        end
    end, false)
    
    RegisterCommand('towradio', function()
        if hasRequiredJob() then
            toggleRadio(not state.radioActive)
        end
    end, false)
    
    if Config.EnableDispatchHotkey then
        RegisterKeyMapping(Config.DispatchCommand, 'Request tow job', 'keyboard', Config.DispatchKeybind)
    end
    
    if Config.UseRadioSystem then
        RegisterKeyMapping('towradio', 'Toggle tow radio', 'keyboard', Config.RadioKeybind)
    end
    
    return function()
        if startBlip and DoesBlipExist(startBlip) then
            RemoveBlip(startBlip)
        end
        
        if state.jobZone then
            state.jobZone:remove()
        end
        
        if state.deliveryZone then
            state.deliveryZone:remove()
        end
        
        lib.hideTextUI()
    end
end

lib.onCache('vehicle', function(vehicle, oldVehicle)
    if not vehicle and oldVehicle == state.towingVehicle then
        state.lastCoords = nil
    end
    
    if state.deliveryZone and state.isTowing and state.targetVehicle then
        if vehicle == state.towingVehicle and IsEntityInZone(cache.ped, state.deliveryZone) then
            lib.showTextUI('[E] Deliver Vehicle', {position = 'top-center'})
        else
            lib.hideTextUI()
        end
    end
end)

lib.onCache('seat', function(seat)
    if state.deliveryZone and state.isTowing and state.targetVehicle and cache.vehicle == state.towingVehicle then
        if seat == -1 and IsEntityInZone(cache.ped, state.deliveryZone) then
            lib.showTextUI('[E] Deliver Vehicle', {position = 'top-center'})
        else
            lib.hideTextUI()
        end
    end
end)

RegisterNetEvent('lation_towtruck:receivedPayment', function(amount)
    showNotification('You received $' .. amount .. ' for your service', 'success')
end)

RegisterNetEvent('lation_towtruck:vehicleTowState', function(netId, towTruckNetId, towState)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local towTruck = NetworkGetEntityFromNetworkId(towTruckNetId)
    
    if not vehicle or not DoesEntityExist(vehicle) then return end
    
    if towState then
        state.isTowing = true
        state.targetVehicle = vehicle
        state.towingVehicle = towTruck
        SetEntityAlpha(vehicle, 200, false)
    else
        if vehicle == state.targetVehicle then
            state.isTowing = false
            state.targetVehicle = nil
        end
        SetEntityAlpha(vehicle, 255, false)
    end
end)

RegisterNetEvent('lation_towtruck:assignJob', function(location, isEmergency, vehicleNetId)
    if not state.onDuty then return end
    
    state.jobActive = true
    state.isEmergencyJob = isEmergency
    state.lastJobTime = GetGameTimer()
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not vehicle or not DoesEntityExist(vehicle) then
        showNotification('Error with assigned vehicle', 'error')
        return
    end
    
    local blipData = isEmergency and {
        sprite = 380,
        color = 1,
        scale = 0.7,
        name = 'Emergency Vehicle'
    } or Config.Blips.pickupVehicle
    
    if isEmergency then
        state.emergencyBlip = createBlip(location, blipData.sprite, blipData.color, blipData.name, blipData.scale, true)
    else
        state.towBlip = createBlip(location, blipData.sprite, blipData.color, blipData.name, blipData.scale, true)
    end
    
    local deliveryData = Config.Blips.dropOff
    state.deliveryBlip = createBlip(Config.DeliverLocation, deliveryData.sprite, deliveryData.color, deliveryData.name, deliveryData.scale, false)
    
    state.lastCoords = cache.coords
    showNotification(Notifications.jobAssigned, 'success')
end)

CreateThread(function()
    Wait(1000)
    loadFramework()
    local cleanup = InitializeTowingSystem()
    
    AddEventHandler('onResourceStop', function(resource)
        if resource == GetCurrentResourceName() then
            if cleanup then cleanup() end
            
            if state.isTowing and state.targetVehicle and DoesEntityExist(state.targetVehicle) then
                TriggerServerEvent('lation_towtruck:stopTowing', NetworkGetNetworkIdFromEntity(state.targetVehicle))
            end
            
            lib.hideTextUI()
        end
    end)
    
    while true do
        local sleep = 1000
        
        if state.onDuty or hasRequiredJob() then
            sleep = 200
            HandleKeypress()
            TrackDistance()
        end
        
        if Config.CleanupAbandonedTows and state.jobActive then
            if (state.towBlip and DoesBlipExist(state.towBlip)) then
                local blipCoords = GetBlipCoords(state.towBlip)
                if #(cache.coords - blipCoords) > Config.BlipClearDistance and GetGameTimer() - state.lastJobTime > Config.AbandonDistance then
                    TriggerServerEvent('lation_towtruck:abandonJob')
                    state.jobActive = false
                    state.towBlip = removeBlip(state.towBlip)
                    state.deliveryBlip = removeBlip(state.deliveryBlip)
                    state.emergencyBlip = removeBlip(state.emergencyBlip)
                    showNotification('The job was cancelled due to abandonment', 'error')
                end
            end
        end
        
        Wait(sleep)
    end
end)