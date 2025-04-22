local QBCore, ESX, QBX = nil, nil, nil
local PlayerJob = {}
local isTowing = false
local towingVehicle = nil
local targetVehicle = nil
local towBlip = nil
local deliveryBlip = nil
local emergencyBlip = nil
local onDuty = false
local jobCooldown = false
local distanceAccumulator = 0
local lastUpdateTime = 0
local jobActive = false
local lastJobTime = 0
local playerStats = {
    vehiclesTowedCount = 0,
    emergencyJobsCompleted = 0,
    civilianJobsCompleted = 0,
    totalEarned = 0,
    distanceDriven = 0,
    repairsPerformed = 0
}
local startTime = 0
local lastCoords = nil
local isEmergencyJob = false
local radioActive = false
local jobZone = nil
local deliveryZone = nil
local function loadFramework()
    if Config.Framework == 'qbcore' then
        QBCore = exports['qb-core']:GetCoreObject()
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            PlayerJob = QBCore.Functions.GetPlayerData().job
            FetchPlayerStats()
        end)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
            PlayerJob = JobInfo
        end)
    elseif Config.Framework == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
        RegisterNetEvent('esx:playerLoaded', function(xPlayer)
            PlayerJob = xPlayer.job
            FetchPlayerStats()
        end)
        RegisterNetEvent('esx:setJob', function(job)
            PlayerJob = job
        end)
    elseif Config.Framework == 'qbx' then
        QBX = exports.qbx_core
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            PlayerJob = QBX:GetPlayerData().job
            FetchPlayerStats()
        end)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
            PlayerJob = JobInfo
        end)
    end
end
local function FetchPlayerStats()
    if not Config.EnableStats then return end
    playerStats = lib.callback.await('lation_towtruck:getPlayerStats', false) or playerStats
end
local function showNotification(message, type)
    if Config.Framework == 'qbcore' then
        QBCore.Functions.Notify(message, type)
    elseif Config.Framework == 'esx' then
        ESX.ShowNotification(message)
    elseif Config.Framework == 'qbx' then
        QBX:Notify(message, type)
    else
        lib.notify({
            title = Notifications.title,
            description = message,
            icon = Notifications.icon,
            position = Notifications.position,
            type = type or 'info'
        })
    end
end
local function hasRequiredJob()
    if not Config.RequireJob then return true end
    return lib.callback.await('lation_towtruck:checkJob', false)
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
    if not dict or not anim or not duration then return end
    local timeoutCount = 0
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) and timeoutCount < 100 do 
        Wait(10)
        timeoutCount = timeoutCount + 1
    end
    if not HasAnimDictLoaded(dict) then
        showNotification('Failed to load animation', 'error')
        return false
    end
    local ped = PlayerPedId()
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration, 49, 0, false, false, false)
    SetTimeout(duration, function()
        if IsEntityPlayingAnim(ped, dict, anim, 3) then
            ClearPedTasks(ped)
        end
    end)
    return true
end
local function toggleRadio(state)
    radioActive = state
    if Config.UseInteractSound and radioActive then
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'towradio', 0.1)
    end
    showNotification(radioActive and 'Tow dispatch radio activated' or 'Tow dispatch radio deactivated', radioActive and 'success' or 'error')
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
    targetVehicle = vehicle
    isTowing = true
    showNotification(Notifications.successfulVehicleLoad, 'success')
    return true
end
local function detachVehicle()
    if not isTowing or not targetVehicle then
        showNotification(Notifications.noVehicleToUnload, 'error')
        return false
    end
    local canDetach = lib.callback.await('lation_towtruck:canDetachVehicle', false, NetworkGetNetworkIdFromEntity(targetVehicle))
    if not canDetach then
        showNotification('You cannot detach this vehicle', 'error')
        return false
    end
    if not playAnimation(Config.AnimDict, Config.AnimName, Config.DetachAnimationDuration) then
        return false
    end
    local vehNetId = NetworkGetNetworkIdFromEntity(targetVehicle)
    TriggerServerEvent('lation_towtruck:stopTowing', vehNetId)
    targetVehicle = nil
    isTowing = false
    showNotification(Notifications.sucessfulVehicleUnload, 'success')
    return true
end
local function deliverVehicle()
    if not isTowing or not targetVehicle then
        showNotification(Notifications.noVehicleToUnload, 'error')
        return false
    end
    if not playAnimation(Config.AnimDict, Config.AnimName, Config.DeliverAnimationDuration) then
        return false
    end
    local vehNetId = NetworkGetNetworkIdFromEntity(targetVehicle)
    local payment = lib.callback.await('lation_towtruck:deliverVehicle', false, vehNetId, isEmergencyJob)
    if payment then
        showNotification('You received $' .. payment .. ' for the delivery', 'success')
        if lib.callback.await('lation_towtruck:cleanupDelivery', false, vehNetId) then
            targetVehicle = nil
            isTowing = false
            isEmergencyJob = false
            jobActive = false
            removeBlip(towBlip)
            removeBlip(deliveryBlip)
            removeBlip(emergencyBlip)
            if lastCoords then
                local currentCoords = GetEntityCoords(PlayerPedId())
                local jobDistance = #(currentCoords - lastCoords)
                playerStats.distanceDriven = playerStats.distanceDriven + jobDistance
            end
            if Config.EnableStats then
                playerStats.vehiclesTowedCount = playerStats.vehiclesTowedCount + 1
                playerStats.totalEarned = playerStats.totalEarned + payment
                if isEmergencyJob then
                    playerStats.emergencyJobsCompleted = playerStats.emergencyJobsCompleted + 1
                else
                    playerStats.civilianJobsCompleted = playerStats.civilianJobsCompleted + 1
                end
                TriggerServerEvent('lation_towtruck:saveStats', playerStats)
            end
            if Config.UseJobUI and onDuty then
                CreateJobDialog()
            end
            return true
        end
    end
    showNotification('Failed to process delivery', 'error')
    return false
end
local function repairVehicle()
    if not targetVehicle then
        showNotification('No vehicle to repair', 'error')
        return false
    end
    local vehNetId = NetworkGetNetworkIdFromEntity(targetVehicle)
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
    if not towingVehicle then
        showNotification('No tow truck to maintain', 'error')
        return false
    end
    local vehNetId = NetworkGetNetworkIdFromEntity(towingVehicle)
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
    if not hasRequiredJob() then
        showNotification(Notifications.notAuthorized, 'error')
        return nil
    end
    local result = lib.callback.await('lation_towtruck:spawnTowTruck', false)
    if not result then
        showNotification('Failed to spawn tow truck', 'error')
        return nil
    end
    towingVehicle = NetworkGetEntityFromNetworkId(result)
    if not towingVehicle or not DoesEntityExist(towingVehicle) then
        showNotification('Error retrieving spawned vehicle', 'error')
        return nil
    end
    return towingVehicle
end
local function clockIn()
    if not hasRequiredJob() then
        showNotification(Notifications.notAuthorized, 'error')
        return false
    end
    if not lib.callback.await('lation_towtruck:clockIn', false) then
        showNotification('Failed to clock in', 'error')
        return false
    end
    onDuty = true
    showNotification(Notifications.clockedIn, 'success')
    if Config.AutoAssignJobs then
        SetTimeout(math.random(Config.MinWaitTime * 60000, Config.MaxWaitTime * 60000), function()
            if onDuty and not jobActive then
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
    onDuty = false
    isEmergencyJob = false
    jobActive = false
    removeBlip(towBlip)
    removeBlip(deliveryBlip)
    removeBlip(emergencyBlip)
    if towingVehicle and DoesEntityExist(towingVehicle) then
        if IsPedInVehicle(PlayerPedId(), towingVehicle, false) then
            TaskLeaveVehicle(PlayerPedId(), towingVehicle, 0)
            Wait(1500)
        end
        TriggerServerEvent('lation_towtruck:deleteTowTruck', NetworkGetNetworkIdFromEntity(towingVehicle))
        towingVehicle = nil
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
                description = onDuty and ContextMenu.clockInDescription2 or ContextMenu.clockInDescription,
                icon = ContextMenu.clockInIcon,
                disabled = onDuty,
                onSelect = function()
                    if not onDuty then
                        clockIn()
                    end
                end
            },
            {
                title = ContextMenu.clockOutTitle,
                description = onDuty and ContextMenu.clockOutDescription or ContextMenu.clockOutDescription2,
                icon = ContextMenu.clockOutIcon,
                disabled = not onDuty,
                onSelect = function()
                    if onDuty then
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
                    SetTimeout(math.random(Config.MinWaitTime * 60000, Config.MaxWaitTime * 60000), function()
                        if onDuty and not jobActive then
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
                   not towingVehicle or 
                   not DoesEntityExist(towingVehicle) or
                   IsPedInAnyVehicle(PlayerPedId(), false) or
                   isTowing or
                   entity == towingVehicle then 
                    return false 
                end
                local towPos = GetEntityCoords(towingVehicle)
                local entityPos = GetEntityCoords(entity)
                return #(towPos - entityPos) <= Config.TowingRange
            end,
            onSelect = function(data)
                attachVehicle(towingVehicle, data.entity)
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
                       not IsPedInAnyVehicle(PlayerPedId(), false) and
                       isTowing and 
                       entity == towingVehicle
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
                       not IsPedInAnyVehicle(PlayerPedId(), false) and
                       isTowing and 
                       entity == towingVehicle
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
                       not IsPedInAnyVehicle(PlayerPedId(), false) and
                       entity == towingVehicle
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
    if jobZone then
        jobZone:remove()
        jobZone = nil
    end
    if deliveryZone then
        deliveryZone:remove()
        deliveryZone = nil
    end
    jobZone = lib.zones.sphere({
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
    deliveryZone = lib.zones.sphere({
        coords = Config.DeliverLocation,
        radius = Config.DeliverRadius,
        debug = false,
        onEnter = function()
            if isTowing and targetVehicle and IsPedInVehicle(PlayerPedId(), towingVehicle, false) then
                lib.showTextUI('[E] Deliver Vehicle', {position = 'top-center'})
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end
    })
end
local function InitializeTowingSystem()
    local blipData = Config.Blips.startJob
    local startBlip = createBlip(Config.StartJobLocation, blipData.blipSprite, blipData.blipColor, blipData.blipName, blipData.blipScale, false)
    SetupTargetSystem()
    SetupZones()
    local jobPed = nil
    if Config.SpawnStartJobNPC then
        jobPed = lib.callback.await('lation_towtruck:spawnJobPed', false)
    end
    RegisterCommand(Config.DispatchCommand, function()
        if hasRequiredJob() and onDuty and not jobActive then
            TriggerServerEvent('lation_towtruck:requestJob', false)
        end
    end, false)
    RegisterCommand('towemergency', function()
        if hasRequiredJob() and onDuty and not jobActive then
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
            toggleRadio(not radioActive)
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
        if jobZone then
            jobZone:remove()
        end
        if deliveryZone then
            deliveryZone:remove()
        end
        lib.hideTextUI()
    end
end
local function HandleKeypress()
    if IsControlJustPressed(0, 38) then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        if isTowing and targetVehicle and #(coords - Config.DeliverLocation) < Config.DeliverRadius and IsPedInVehicle(ped, towingVehicle, false) then
            deliverVehicle()
        end
        if hasRequiredJob() and #(coords - Config.StartJobLocation) < 3.0 and not IsPedInAnyVehicle(ped, false) then
            CreateTowMenu()
        end
    end
end
CreateThread(function()
    while true do
        Wait(2000)
        if Config.EnableStats and onDuty and towingVehicle and DoesEntityExist(towingVehicle) then
            local ped = PlayerPedId()
            if IsPedInVehicle(ped, towingVehicle, false) then
                local currentCoords = GetEntityCoords(ped)
                if lastCoords then
                    local distance = #(currentCoords - lastCoords)
                    if distance > 5.0 then
                        distanceAccumulator = distanceAccumulator + distance
                        lastCoords = currentCoords
                        playerStats.distanceDriven = playerStats.distanceDriven + distance
                        local currentTime = GetGameTimer()
                        if distanceAccumulator > 200.0 or (currentTime - lastUpdateTime) > 60000 then
                            TriggerServerEvent('lation_towtruck:updateDistance', playerStats.distanceDriven)
                            distanceAccumulator = 0
                            lastUpdateTime = currentTime
                        end
                    end
                else
                    lastCoords = currentCoords
                end
            end
        end
    end
end)
CreateThread(function()
    Wait(1000)
    loadFramework()
    local cleanup = InitializeTowingSystem()
    AddEventHandler('onResourceStop', function(resource)
        if resource == GetCurrentResourceName() then
            if cleanup then cleanup() end
            if isTowing and targetVehicle and DoesEntityExist(targetVehicle) then
                TriggerServerEvent('lation_towtruck:stopTowing', NetworkGetNetworkIdFromEntity(targetVehicle))
            end
            lib.hideTextUI()
        end
    end)
    while true do
        local sleep = 1000
        if onDuty or hasRequiredJob() then
            sleep = 200
            HandleKeypress()
            TrackDistance()
        end
        if Config.CleanupAbandonedTows and jobActive then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            if towBlip and DoesBlipExist(towBlip) then
                local blipCoords = GetBlipCoords(towBlip)
                if #(coords - blipCoords) > Config.BlipClearDistance and GetGameTimer() - lastJobTime > Config.AbandonDistance then
                    TriggerServerEvent('lation_towtruck:abandonJob')
                    jobActive = false
                    removeBlip(towBlip)
                    removeBlip(deliveryBlip)
                    removeBlip(emergencyBlip)
                    showNotification('The job was cancelled due to abandonment', 'error')
                end
            end
        end
        Wait(sleep)
    end
end)
RegisterNetEvent('lation_towtruck:receivedPayment', function(amount)
    showNotification('You received $' .. amount .. ' for your service', 'success')
end)
RegisterNetEvent('lation_towtruck:vehicleTowState', function(netId, towTruckNetId, state)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local towTruck = NetworkGetEntityFromNetworkId(towTruckNetId)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    if state then
        isTowing = true
        targetVehicle = vehicle
        towingVehicle = towTruck
        SetEntityAlpha(vehicle, 200, false)
    else
        if vehicle == targetVehicle then
            isTowing = false
            targetVehicle = nil
        end
        SetEntityAlpha(vehicle, 255, false)
    end
end)
RegisterNetEvent('lation_towtruck:assignJob', function(location, isEmergency, vehicleNetId)
    if not onDuty then return end
    jobActive = true
    isEmergencyJob = isEmergency
    lastJobTime = GetGameTimer()
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
        emergencyBlip = createBlip(location, blipData.sprite, blipData.color, blipData.name, blipData.scale, true)
    else
        towBlip = createBlip(location, blipData.sprite, blipData.color, blipData.name, blipData.scale, true)
    end
    local deliveryData = Config.Blips.dropOff
    deliveryBlip = createBlip(Config.DeliverLocation, deliveryData.sprite, deliveryData.color, deliveryData.name, deliveryData.scale, false)
    lastCoords = GetEntityCoords(PlayerPedId())
    showNotification(Notifications.jobAssigned, 'success')
end)