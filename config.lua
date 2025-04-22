Config = {}

-- Framework Settings
Config.Framework = 'standalone' -- 'esx', 'qbcore' or 'standalone'
Config.RequireJob = false
Config.JobName = 'mechanic'
Config.Vehiclekeys = 'QBox'

-- Core Job Settings
Config.TowTruckModel = `flatbed`
Config.StartJobPedModel = `a_m_m_business_01`
Config.StartJobLocation = vec3(1242.0847, -3257.0403, 5.0288)
Config.DeliverLocation = vec3(393.0399, -1617.5004, 29.2920)
Config.DeliverRadius = 10
Config.StartJobRadius = 50
Config.StartJobPedHeading = 272.1205
Config.SpawnTruckLocation = vector3(1247.0011, -3262.6636, 5.8075)
Config.SpawnTruckHeading = 269.8075
Config.MinWaitTime = 1
Config.MaxWaitTime = 2
Config.BlipClearDistance = 150.0
Config.TowingRange = 5.0
Config.JobCooldown = 10000
Config.EmergencyCooldown = 5000

-- Vehicle Settings
Config.MinVehicleHealth = 100
Config.MaxVehicleHealth = 400
Config.DisableVehicleEngines = true
Config.TowOffset = {x = -0.5, y = -5.0, z = 1.0}
Config.TowRotation = {x = 0.0, y = 0.0, z = 0.0}
Config.AttachBone = 20
Config.AttachAnimationDuration = 5000
Config.DetachAnimationDuration = 5000
Config.DeliverAnimationDuration = 5000

-- Payment Settings
Config.PayPerDelivery = 500
Config.PayPerDeliveryAccount = 'money'
Config.RandomPayPerDelivery = true
Config.MinPayPerDelivery = 350
Config.MaxPayPerDelivery = 950
Config.EmergencyPayMultiplier = 1.5
Config.RepairCost = 150
Config.MaintenanceCost = 100

-- Feature Toggles
Config.EnableStats = true
Config.PersistentStats = true
Config.SpawnStartJobNPC = true
Config.ShowStartJobMarker = false
Config.ShowJobSearchNotification = false
Config.EmergencyEffects = true
Config.UseRadioSystem = true
Config.UseInteractSound = false
Config.EnableForcedTowMode = true
Config.CleanupAbandonedTows = true
Config.EnableDispatchHotkey = true
Config.EnableServerLogs = true

-- Animation Settings
Config.AnimDict = 'mini@repair'
Config.AnimName = 'fixing_a_ped'
Config.RepairDuration = 10000
Config.MaintenanceDuration = 8000
Config.AbandonDistance = 3000

-- Commands & Keybinds
Config.DispatchCommand = 'towtruck'
Config.DispatchKeybind = 'F6'
Config.RadioKeybind = 'F7'
Config.JobMenuCommand = 'towmenu'

-- Security Settings
Config.MaxInteractionDistance = 10.0
Config.VehicleCleanupTime = 3600
Config.JobVehicleTimeout = 1800
Config.TowedVehicleTimeout = 1800

-- Emergency Locations
Config.EmergencyLocations = {
    vector4(233.4, -779.2, 30.6, 69.3),
    vector4(1156.6, -1643.5, 36.9, 213.1),
    vector4(-511.8, -1075.4, 23.5, 88.7),
    vector4(384.2, -1631.8, 29.3, 320.4),
    vector4(-1194.6, -876.3, 13.4, 121.6)
}

-- Map Blips
Config.Blips = {
    startJob = {
        blipSprite = 477,
        blipColor = 21,
        blipScale = 0.7,
        blipName = 'Towing'
    },
    pickupVehicle = {
        blipSprite = 380,
        blipColor = 1,
        blipScale = 0.7,
        blipName = 'Target Vehicle'
    },
    dropOff = {
        blipSprite = 68,
        blipColor = 2,
        blipScale = 0.7,
        blipName = 'Target Drop Off'
    }
}

-- Vehicle Spawn Locations
Config.Locations = {
    { x = 1015.3276, y = -2462.3572, z = 27.7853, h = 82.8159 },
    { x = -247.7807, y = -1687.8434, z = 33.4754, h = 178.8647 },
    { x = 372.9686, y = -767.0320, z = 29.2700, h = 0.0682 },
    { x = -1276.2042, y = -556.5905, z = 30.2092, h = 219.8612 },
    { x = 1205.2948, y = -708.5202, z = 59.4169, h = 9.6660 },
    { x = 213.8225, y = 389.6160, z = 106.5621, h = 171.4204 },
    { x = -449.8099, y = 98.6727, z = 62.8731, h = 355.5552 },
    { x = -928.4528, y = -124.9771, z = 37.2992, h = 117.7664 },
    { x = -1772.7124, y = -519.8768, z = 38.5269, h = 299.9457 },
    { x = -2165.7588, y = -420.4905, z = 13.0514, h = 20.4053 },
    { x = -1483.1953, y = -895.6342, z = 9.7399, h = 64.1165 }
}

-- Vehicle Models
Config.CarModels = {
    `felon`,
    `prairie`,
    `baller`,
    `sentinel`,
    `zion`,
    `ruiner`,
    `asea`,
    `ingot`,
    `intruder`,
    `primo`,
    `stratum`,
    `tailgater`
}

-- Notification Settings
Notifications = {
    position = 'top',
    icon = 'truck-ramp-box',
    title = 'Tow Truck',
    notAuthorized = 'You are not authorized to perform this job - you must be a ' ..Config.JobName,
    successfulVehicleLoad = 'You have successfully loaded the vehicle onto the Tow Truck',
    cancelledVehicleLoad = 'You cancelled loading the vehicle',
    notCloseEnough = 'You are not close enough to the vehicle you are trying to tow',
    sucessfulVehicleUnload = 'You have successfully unloaded the vehicle from the Tow Truck',
    cancelledVehicleUnload = 'You cancelled unloading the vehicle',
    error = 'An error has occured - please try again',
    noVehicleToUnload = 'There is no vehicle on the truck to unload',
    towTruckSpawnOccupied = 'The location is currently occupied - please move any vehicles and try again',
    clockedIn = 'You will now start receiving jobs as they become available',
    tooFarToDeliver = 'You are too far from the delivery location to get paid',
    confirmNextJob = 'Great - a new job will be assigned as it becomes available',
    searchingForJob = 'Searching for a new job location..',
    jobAssigned = 'A new job is available - your GPS was updated'
}

-- Target Settings
Target = {
    distance = 2,
    loadVehicle = 'Load vehicle',
    loadVehicleIcon = 'fas fa-truck-ramp-box',
    unloadVehicle = 'Unload vehicle',
    unloadVehicleIcon = 'fas fa-truck-ramp-box',
    startJob = 'Talk',
    startJobIcon = 'fas fa-truck'
}

-- Context Menu Settings
ContextMenu = {
    menuTitle = 'Towing',
    towTruckTitle = 'Tow Truck',
    towTruckDescription = 'Receive your Tow Truck then Clock In to begin work',
    towTruckIcon = 'truck',
    clockInTitle = 'Clock In',
    clockInDescription = 'Show yourself as on-duty & ready to receive calls',
    clockInDescription2 = 'You are already on-duty & receiving calls',
    clockInIcon = 'clock',
    clockOutTitle = 'Clock Out',
    clockOutDescription = 'Return your truck and go off-duty',
    clockOutDescription2 = 'You\'re not clocked in',
    clockOutIcon = 'clock'
}