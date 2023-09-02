---@diagnostic disable: param-type-mismatch
local QBCore = exports['qbx-core']:GetCoreObject()
local PlayerData = {}
local PlayerGang = {}
local PlayerJob = {}
local CurrentHouseGarage = nil
local OutsideVehicles = {}
local CurrentGarage = nil
local GaragePoly = {}
local MenuItemId1 = nil
local MenuItemId2 = nil
local VehicleClassMap = {}
local GarageZones = {}

-- helper functions
function TrackVehicleByPlate(plate)
    local coords = lib.callback.await('qb-garages:server:GetVehicleLocation', false, plate)

    if coords then
        if not IsWaypointActive() then -- Check if waypoints already setted up or not
            SetNewWaypoint(coords.x, coords.y)
            lib.notify({
                id          = 'invalid_plate',
                description = 'Waypoint has been set, check your map',
                type        = 'success'
            })
        else
            lib.notify({
                id          = 'waypoint_pointed',
                description = 'Waypoint already pointed, check your map',
                type        = 'warning'
            })
        end
    else
        lib.notify({
            id          = 'location_pinned',
            description = 'Plate is invalid',
            type        = 'error'
        })
    end
end

exports("TrackVehicleByPlate", TrackVehicleByPlate)

RegisterNetEvent('qb-garages:client:TrackVehicleByPlate', function(plate)
    TrackVehicleByPlate(plate)
end)

local function IsStringNilOrEmpty(s)
    return s == nil or s == ''
end

local function GetSuperCategoryFromCategories(categories)
    local superCategory = 'car'
    if lib.table.contains(categories, { 'car' }) then
        superCategory = 'car'
    elseif lib.table.contains(categories, { 'plane', 'helicopter' }) then
        superCategory = 'air'
    elseif lib.table.contains(categories, 'boat') then
        superCategory = 'sea'
    end
    return superCategory
end

local function GetClosestLocation(locations, loc)
    local closestDistance = -1
    local closestIndex = -1
    local closestLocation = nil
    local plyCoords = loc or GetEntityCoords(cache.ped, true)
    for i, v in ipairs(locations) do
        local location = vector3(v.x, v.y, v.z)
        local distance = #(plyCoords - location)
        if (closestDistance == -1 or closestDistance > distance) then
            closestDistance = distance
            closestIndex = i
            closestLocation = v
        end
    end
    return closestIndex, closestDistance, closestLocation
end

function SetAsMissionEntity(vehicle)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleIsStolen(vehicle, false)
    SetVehicleIsWanted(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
    local id = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(id, true)
end

function GetVehicleByPlate(plate)
    local vehicles = QBCore.Functions.GetVehicles()
    for _, v in pairs(vehicles) do
        if GetPlate(v) == plate then
            return v
        end
    end
    return nil
end

function RemoveRadialOptions()
    if MenuItemId1 then
        exports['qbx-radialmenu']:RemoveOption(MenuItemId1)
        MenuItemId1 = nil
    end
    if MenuItemId2 then
        exports['qbx-radialmenu']:RemoveOption(MenuItemId2)
        MenuItemId2 = nil
    end
end

local function ResetCurrentGarage()
    CurrentGarage = nil
end

--Menus
local function PublicGarage(garageName, type)
    local garage = Config.Garages[garageName]
    local categories = garage.vehicleCategories
    local superCategory = GetSuperCategoryFromCategories(categories)
    lib.registerContext({
        id      = 'qbx_publicVehicle_list',
        title   = garage.label,
        options = {
            {
                title       = Lang:t("menu.header.vehicles"),
                description = Lang:t("menu.text.vehicles"),
                event       = "qb-garages:client:GarageMenu",
                args        = {
                    garageId      = garageName,
                    garage        = garage,
                    categories    = categories,
                    header        = Lang:t("menu.header." .. garage.type .. "_" .. superCategory, { value = garage.label }),
                    superCategory = superCategory,
                    type          = type
                }
            }
        }
    })
    lib.showContext('qbx_publicVehicle_list')
end

local function MenuHouseGarage()
    local superCategory = GetSuperCategoryFromCategories(Config.HouseGarageCategories)
    lib.registerContext({
        id      = 'qbx_houseVehicle_list',
        title   = Lang:t("menu.header.house_garage"),
        options = {
            {
                title       = Lang:t("menu.text.vehicles"),
                description = Lang:t("menu.text.vehicles"),
                event       = "qb-garages:client:GarageMenu",
                args        = {
                    garageId      = CurrentHouseGarage,
                    categories    = Config.HouseGarageCategories,
                    header        = Config.HouseGarages[CurrentHouseGarage].label,
                    garage        = Config.HouseGarages[CurrentHouseGarage],
                    superCategory = superCategory,
                    type          = 'house'
                }
            }
        }
    })
    lib.showContext('qbx_houseVehicle_list')
end

-- Functions
local function ApplyVehicleDamage(currentVehicle, veh)
    local engine = veh.engine + 0.0
    local body = veh.body + 0.0
    local tyres, windows, doors
    local damage = veh.damage
    local tank = veh.tank + 0.0

    if damage then
        if damage.tyres then
            for k, tyre in pairs(damage.tyres) do
                if tyre.onRim then
                    tyres = tonumber(k)
                elseif tyre.burst then
                    tyres = tonumber(k)
                end
            end
        end
        if damage.windows then
            for k, window in pairs(damage.windows) do
                if window.smashed then
                    windows = tonumber(k)
                end
            end
        end

        if damage.doors then
            for k, door in pairs(damage.doors) do
                if door.damaged then
                    doors = tonumber(k)
                end
            end
        end
    end

    lib.setVehicleProperties(currentVehicle, {
        bodyHealth   = body,
        engineHealth = engine,
        tyres        = { tyres },
        windows      = { windows },
        doors        = { doors },
        tankHealth   = tank
    })
end

local function ExitAndDeleteVehicle(vehicle)
    local garage = Config.Garages[CurrentGarage]
    local props_ = lib.getVehicleProperties(vehicle)
    if not props_ then return end
    local exitLocation = nil
    if garage and garage.ExitWarpLocations and next(garage.ExitWarpLocations) then
        _, _, exitLocation = GetClosestLocation(garage.ExitWarpLocations)
    end
    for i = -1, 5, 1 do
        if cache.seat == i then
            TaskLeaveVehicle(cache.ped, vehicle, 0)
            if exitLocation then
                SetEntityCoords(cache.ped, exitLocation.x, exitLocation.y, exitLocation.z, false, false, false, false)
            end
        end
    end
    SetVehicleDoorsLocked(vehicle, 2)
    RemoveRadialOptions()
    Wait(1500)
    DeleteVehicle(vehicle)
    Wait(1000)
    TriggerServerEvent('qb-garages:server:parkVehicle', props_.plate)
end

local function GetVehicleCategoriesFromClass(class)
    return VehicleClassMap[class]
end

local function IsAuthorizedToAccessGarage(garageName)
    local garage = Config.Garages[garageName]
    if not garage then return false end
    if garage.type == 'job' then
        if type(garage.job) == "string" and not IsStringNilOrEmpty(garage.job) then
            return PlayerJob.name == garage.job
        elseif type(garage.job) == "table" then
            return lib.table.contains(garage.job, PlayerJob.name)
        else
            lib.notify({ description = 'job not defined on garage', type = 'error', duration = 7500 })
            return false
        end
    elseif garage.type == 'gang' then
        if type(garage.gang) == "string" and not IsStringNilOrEmpty(garage.gang) then
            return garage.gang == PlayerGang.name
        elseif type(garage.gang) == "table" then
            return lib.table.contains(garage.gang, PlayerGang.name)
        else
            lib.notify({ description = 'job not defined on garage', type = 'error', duration = 7500 })
            return false
        end
    end
    return true
end

local function CanParkVehicle(veh, garageName, vehLocation)
    local garage = garageName and Config.Garages[garageName] or (CurrentGarage and Config.Garages[CurrentGarage] or Config.HouseGarages[CurrentHouseGarage])
    if not garage then return false end
    local parkingDistance = garage.ParkingDistance and garage.ParkingDistance or Config.ParkingDistance
    local vehClass = GetVehicleClass(veh)
    local vehCategories = GetVehicleCategoriesFromClass(vehClass)
    if garage and garage.vehicleCategories and not lib.table.contains(garage.vehicleCategories, vehCategories) then
        lib.notify({ description = Lang:t("error.not_correct_type"), type = 'error', duration = 4500 })
        return false
    end
    local parkingSpots = garage.ParkingSpots and garage.ParkingSpots or {}
    if next(parkingSpots) then
        local _, closestDistance, closestLocation = GetClosestLocation(parkingSpots, vehLocation)
        if closestDistance >= parkingDistance then
            lib.notify({ description = Lang:t("error.too_far_away"), type = 'error', duration = 4500 })
            return false
        else
            return true, closestLocation
        end
    else
        return true
    end
end

local function ParkOwnedVehicle(veh, garageName, vehLocation, plate)
    local props_ = lib.getVehicleProperties(veh)
    if not props_ then return end
    local fuel = exports[Config.FuelScript]:GetFuel(veh)
    local canPark, closestLocation = CanParkVehicle(veh, garageName, vehLocation)
    local closestVec3 = closestLocation and vector3(closestLocation.x, closestLocation.y, closestLocation.z) or nil
    if not canPark and not garageName.useVehicleSpawner then return end
    TriggerServerEvent('qb-garage:server:updateVehicle', 1, fuel, props_.engineHealth, props_.bodyHealth, props_.tankHealth, props_, plate, garageName, Config.StoreParkinglotAccuratly and closestVec3 or nil)
    ExitAndDeleteVehicle(veh)
    if plate then
        OutsideVehicles[plate] = nil
        TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
    end
    lib.notify({ description = Lang:t("success.vehicle_parked"), type = 'success', duration = 4500 })
end

function ParkVehicleSpawnerVehicle(veh, garageName, vehLocation, plate)
    lib.callback("qb-garage:server:checkspawnedvehicle", false, function(result)
        local canPark, _ = CanParkVehicle(veh, garageName, vehLocation)
        if result and canPark then
            TriggerServerEvent("qb-garage:server:UpdateSpawnedVehicle", plate, nil)
            ExitAndDeleteVehicle(veh)
        elseif not result then
            lib.notify({ id = 'not_owned', description = Lang:t("error.not_owned"), type = 'error' })
        end
    end, plate)
end

local function ParkVehicle(veh, garageName, vehLocation)
    local plate = GetPlate(veh)
    local garageName = garageName or (CurrentGarage or CurrentHouseGarage)
    local garage = Config.Garages[garageName]
    local type = garage and garage.type or 'house'
    local gang = PlayerGang.name;
    local job = PlayerJob.name;
    local owned = lib.callback.await('qb-garage:server:checkOwnership', false, plate, type, garageName, gang)
    if owned then
        ParkOwnedVehicle(veh, garageName, vehLocation, plate)
    elseif garage and garage.useVehicleSpawner and IsAuthorizedToAccessGarage(garageName) then
        ParkVehicleSpawnerVehicle(veh, vehLocation, vehLocation, plate)
    else
        lib.notify({ id = 'not_owned', description = Lang:t("error.not_owned"), type = 'error' })
    end
end

local function AddRadialParkingOption()
    if cache.vehicle and cache.seat == -1 then
        if MenuItemId1 then return end
        if MenuItemId2 then
            exports['qbx-radialmenu']:RemoveOption(MenuItemId2)
        end
        MenuItemId1 = exports['qbx-radialmenu']:AddOption({
            id          = 'put_up_vehicle',
            title       = 'Park Vehicle',
            icon        = 'square-parking',
            type        = 'client',
            event       = 'qb-garages:client:ParkVehicle',
            shouldClose = true
        }, MenuItemId1)
    end
    if not cache.vehicle or not cache.seat then
        if MenuItemId2 then return end
        if MenuItemId1 then
            exports['qbx-radialmenu']:RemoveOption(MenuItemId1)
        end
        MenuItemId2 = exports['qbx-radialmenu']:AddOption({
            id          = 'open_garage_menu',
            title       = 'Open Garage',
            icon        = 'warehouse',
            type        = 'client',
            event       = 'qb-garages:client:OpenMenu',
            shouldClose = true
        }, MenuItemId2)
    end
end

local function AddRadialImpoundOption()
    if MenuItemId1 then return end
    MenuItemId1 = exports['qbx-radialmenu']:AddOption({
        id          = 'open_garage_menu',
        title       = 'Open Impound Lot',
        icon        = 'warehouse',
        type        = 'client',
        event       = 'qb-garages:client:OpenMenu',
        shouldClose = true
    }, MenuItemId1)
end

local function UpdateRadialMenu(garagename)
    CurrentGarage = garagename or CurrentGarage or nil
    local garage = Config.Garages[CurrentGarage]
    if CurrentGarage and garage then
        if garage.type == 'job' and not IsStringNilOrEmpty(garage.job) then
            if IsAuthorizedToAccessGarage(CurrentGarage) then
                AddRadialParkingOption()
            end
        elseif garage.type == 'gang' and not IsStringNilOrEmpty(garage.gang) then
            if PlayerGang.name == garage.gang then
                AddRadialParkingOption()
            end
        elseif garage.type == 'depot' then
            AddRadialImpoundOption()
        elseif IsAuthorizedToAccessGarage(CurrentGarage) then
            AddRadialParkingOption()
        end
    elseif CurrentHouseGarage then
        AddRadialParkingOption()
    else
        RemoveRadialOptions()
    end
end

local function RegisterHousePoly(house)
    if GaragePoly[house] then return end
    local coords = Config.HouseGarages[house].takeVehicle
    if not coords or not coords.x then return end
    local pos = vector3(coords.x, coords.y, coords.z)
    GaragePoly[house] = lib.zones.box({
        coords   = pos,
        size     = vec3(7.5, 7.5, 5),
        rotation = coords.h or coords.w,
        debug    = true,
        onEnter  = function()
            CurrentHouseGarage = house
            UpdateRadialMenu()
            lib.showTextUI(Config.HouseParkingDrawText, {
                position  = Config.DrawTextPosition,
                icon      = { 'fas', 'square-parking' },
                iconColor = '#0096FF'
            })
        end,
        onExit   = function()
            if lib.isTextUIOpen() then
                lib.hideTextUI()
            end
            RemoveRadialOptions()
            CurrentHouseGarage = nil
        end
    })
end

local function RemoveHousePoly(house)
    if not GaragePoly[house] then return end
    GaragePoly[house]:remove()
    GaragePoly[house] = nil
end

function JobMenuGarage(garageName)
    local job = QBCore.Functions.GetPlayerData().job.name
    local garage = Config.Garages[garageName]
    local jobGarage = Config.JobVehicles[garage.jobGarageIdentifier]

    if not jobGarage then
        if garage.jobGarageIdentifier then
            TriggerEvent('ox_lib:notify', {
                description = string.format('Job garage with id %s not configured.', garage.jobGarageIdentifier),
                type        = 'error',
                duration    = 5000
            })
        else
            TriggerEvent('ox_lib:notify', {
                description = string.format("'jobGarageIdentifier' not defined on job garage %s ", garageName),
                type        = 'error',
                duration    = 5000
            })
        end
        return
    end

    local vehicleMenu = {
        id      = 'qbx_jobVehicle_Menu',
        title   = jobGarage.label,
        options = {}
    }

    local vehicles = jobGarage.vehicles[QBCore.Functions.GetPlayerData().job.grade.level]
    for veh, label in pairs(vehicles) do
        vehicleMenu[#vehicleMenu + 1] = {
            title       = label,
            description = "",
            event       = "qb-garages:client:TakeOutGarage",
            args        = {
                vehicleModel = veh,
                garage       = garage
            }
        }
    end
    lib.registerContext(vehicleMenu)
    lib.showContext('qbx_jobVehicle_Menu')
end

function GetFreeParkingSpots(parkingSpots)
    local freeParkingSpots = {}
    for _, parkingSpot in ipairs(parkingSpots) do
        local veh, distance = QBCore.Functions.GetClosestVehicle(vector3(parkingSpot.x, parkingSpot.y, parkingSpot.z))
        if not veh or distance >= 1.5 then
            freeParkingSpots[#freeParkingSpots + 1] = parkingSpot
        end
    end
    return freeParkingSpots
end

function GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
    local checkAt = nil
    if Config.StoreParkinglotAccuratly and Config.SpawnAtLastParkinglot and vehicle and vehicle.parkingspot then
        checkAt = vector3(vehicle.parkingspot.x, vehicle.parkingspot.y, vehicle.parkingspot.z) or nil
    end
    local _, _, location = GetClosestLocation(freeParkingSpots, checkAt)
    return location
end

function GetSpawnLocationAndHeading(garage, garageType, parkingSpots, vehicle, spawnDistance)
    local location
    local heading
    local closestDistance = -1

    if garageType == "house" then
        location = garage.takeVehicle
        heading = garage.takeVehicle.h -- yes its 'h' not 'w'...
    else
        if next(parkingSpots) then
            local freeParkingSpots = GetFreeParkingSpots(parkingSpots)
            if Config.AllowSpawningFromAnywhere then
                location = GetFreeSingleParkingSpot(freeParkingSpots, vehicle)
                if location == nil then
                    lib.notify({ description = Lang:t("error.all_occupied"), type = 'error', duration = 4500 })
                    return
                end
                heading = location.w
            else
                _, closestDistance, location = GetClosestLocation(Config.SpawnAtFreeParkingSpot and freeParkingSpots or parkingSpots)
                if not location then return end
                local plyCoords = GetEntityCoords(cache.ped, false)
                local spot = vector3(location.x, location.y, location.z)
                if Config.SpawnAtLastParkinglot and vehicle and vehicle.parkingspot then
                    spot = vehicle.parkingspot
                end
                local dist = #(plyCoords - vector3(spot.x, spot.y, spot.z))
                if Config.SpawnAtLastParkinglot and dist >= spawnDistance then
                    lib.notify({ description = Lang:t("error.too_far_away"), type = 'error', duration = 4500 })
                    return
                elseif closestDistance >= spawnDistance then
                    lib.notify({ description = Lang:t("error.too_far_away"), type = 'error', duration = 4500 })
                    return
                else
                    local veh, distance = QBCore.Functions.GetClosestVehicle(vector3(location.x, location.y, location.z))
                    if veh and distance <= 1.5 then
                        lib.notify({ description = Lang:t("error.occupied"), type = 'error', duration = 4500 })
                        return
                    end
                    heading = location.w
                end
            end
        else
            local ped = GetEntityCoords(cache.ped)
            local pedheadin = GetEntityHeading(cache.ped)
            local forward = GetEntityForwardVector(cache.ped)
            local x, y, z = table.unpack(ped + forward * 3)
            location = vector3(x, y, z)
            if Config.VehicleHeading == 'forward' then
                heading = pedheadin
            elseif Config.VehicleHeading == 'driverside' then
                heading = pedheadin + 90
            elseif Config.VehicleHeading == 'hood' then
                heading = pedheadin + 180
            elseif Config.VehicleHeading == 'passengerside' then
                heading = pedheadin + 270
            end
        end
    end
    return location, heading
end

function UpdateSpawnedVehicle(spawnedVehicle, vehicleInfo, heading, garage, prop)
    local plate = GetPlate(spawnedVehicle)

    if plate then
        OutsideVehicles[plate] = spawnedVehicle
        TriggerServerEvent('qb-garages:server:UpdateOutsideVehicles', OutsideVehicles)
    end

    exports[Config.FuelScript]:SetFuel(spawnedVehicle, vehicleInfo.fuel)
    lib.setVehicleProperties(spawnedVehicle, prop)
    lib.setVehicleProperties(spawnedVehicle, { plate = vehicleInfo.plate })
    SetAsMissionEntity(spawnedVehicle)
    ApplyVehicleDamage(spawnedVehicle, vehicleInfo)
    TriggerServerEvent('qb-garage:server:updateVehicleState', 0, vehicleInfo.plate, vehicleInfo.garage)
    TriggerEvent("vehiclekeys:client:SetOwner", vehicleInfo.plate)
    SetEntityHeading(spawnedVehicle, heading)
    SetAsMissionEntity(spawnedVehicle)
    SetVehicleEngineOn(spawnedVehicle, true, true, false)
end

-- Events
RegisterNetEvent("qb-garages:client:GarageMenu", function(data)
    local type = data.type
    local garageId = data.garageId
    local garage = data.garage
    local header = data.header
    local superCategory = data.superCategory
    local result = lib.callback.await('qb-garage:server:GetGarageVehicles', false, garageId, type, superCategory)

    if result == nil then
        lib.notify({ id = 'no_vehicles', description = Lang:t("error.no_vehicles"), type = 'error', duration = 5000 })
    else
        MenuGarageOptions = {}
        result = result and result or {}
        for _, v in pairs(result) do
            local enginePercent = math.round(v.engine / 10, 0) .. '%'
            local bodyPercent = math.round(v.body / 10, 0) .. '%'
            local tankPercent = math.round(v.tank / 10, 0) .. '%'
            local currentFuel = math.round(v.fuel / 1, 0) .. '%'
            local vehData = QBCore.Shared.Vehicles[v.vehicle]
            local vname = 'Vehicle does not exist'

            if vehData then
                local vehCategories = GetVehicleCategoriesFromClass(GetVehicleClassFromName(v.vehicle))
                if garage and garage.vehicleCategories and not lib.table.contains(garage.vehicleCategories, vehCategories) then
                    goto continue
                end
                vname = vehData.name
            end

            if v.state == 0 then
                v.state = Lang:t("status.out")
            elseif v.state == 1 then
                v.state = Lang:t("status.garaged")
            elseif v.state == 2 then
                v.state = Lang:t("status.impound")
            end

            if type == "depot" then
                MenuGarageOptions[#MenuGarageOptions + 1] = {
                    title       = Lang:t('menu.header.depot', { value = vname, value2 = v.depotprice }),
                    description = Lang:t('menu.text.depot', { value = v.plate }),
                    colorScheme = 'red',
                    metadata    = {
                        { label = Lang:t('menu.metadata.fuel'),   value = currentFuel,   progress = v.fuel },
                        { label = Lang:t('menu.metadata.engine'), value = enginePercent, progress = v.engine },
                        { label = Lang:t('menu.metadata.body'),   value = bodyPercent,   progress = v.body },
                        { label = Lang:t('menu.metadata.tank'),   value = tankPercent,   progress = v.tank }
                    },
                    event       = "qb-garages:client:TakeOutDepot",
                    args        = {
                        vehicle      = v,
                        vehicleModel = v.vehicle,
                        type         = type,
                        garage       = garage,
                    }
                }
            else
                MenuGarageOptions[#MenuGarageOptions + 1] = {
                    title       = Lang:t('menu.header.garage', { value = vname, value2 = v.plate }),
                    description = Lang:t('menu.text.garage', { value = v.state }),
                    colorScheme = 'red',
                    metadata    = {
                        { label = Lang:t('menu.metadata.fuel'),   value = currentFuel,   progress = v.fuel },
                        { label = Lang:t('menu.metadata.engine'), value = enginePercent, progress = v.engine },
                        { label = Lang:t('menu.metadata.body'),   value = bodyPercent,   progress = v.body },
                        { label = Lang:t('menu.metadata.tank'),   value = tankPercent,   progress = v.tank }
                    },
                    event       = "qb-garages:client:TakeOutGarage",
                    args        = {
                        vehicle       = v,
                        vehicleModel  = v.vehicle,
                        type          = type,
                        garage        = garage,
                        superCategory = superCategory,
                    }
                }
            end
            ::continue::
        end
        lib.registerContext({ id = 'context_garage_carinfo', title = header, options = MenuGarageOptions })
        lib.showContext('context_garage_carinfo')
    end
end)

RegisterNetEvent('qb-garages:client:TakeOutGarage', function(data, cb)
    local garageType = data.type
    local vehicleModel = data.vehicleModel
    local vehicle = data.vehicle
    local garage = data.garage
    local spawnDistance = garage.SpawnDistance and garage.SpawnDistance or Config.SpawnDistance
    local parkingSpots = garage.ParkingSpots or {}

    local location, heading = GetSpawnLocationAndHeading(garage, garageType, parkingSpots, vehicle, spawnDistance)

    local netId, properties = lib.callback.await('qb-garage:server:spawnvehicle', false, vehicle, location,
        garage.WarpPlayerIntoVehicle or Config.WarpPlayerIntoVehicle and garage.WarpPlayerIntoVehicle == nil)

    local timeout = 100

    while not NetworkDoesEntityExistWithNetworkId(netId) and timeout > 0 do
        Wait(10)
        timeout -= 1
    end

    local veh = NetToVeh(netId)
    if not veh or not netId then
        DebugPrint("ISSUE HERE: ", netId)
    end

    UpdateSpawnedVehicle(veh, vehicle, heading, garage, properties)

    if cb then cb(veh) end
end)

RegisterNetEvent('qb-garages:client:OpenMenu', function()
    if CurrentGarage then
        local garage = Config.Garages[CurrentGarage]
        local type = garage.type
        if type == 'job' and garage.useVehicleSpawner then
            JobMenuGarage(CurrentGarage)
        else
            PublicGarage(CurrentGarage, type)
        end
    elseif CurrentHouseGarage then
        TriggerEvent('qb-garages:client:OpenHouseGarage')
    end
end)

RegisterNetEvent('qb-garages:client:ParkVehicle', function()
    local canPark = true
    if Config.AllowParkingFromOutsideVehicle and cache.vehicle == 0 then
        local closestVeh, dist = QBCore.Functions.GetClosestVehicle()
        if dist <= Config.VehicleParkDistance then
            cache.vehicle = closestVeh
        end
    else
        canPark = GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped
    end
    if cache.vehicle ~= 0 and canPark then
        ParkVehicle(cache.vehicle)
    end
end)

RegisterNetEvent('qb-garages:client:ParkLastVehicle', function(parkingName)
    local curVeh = GetLastDrivenVehicle()
    if curVeh then
        local coords = GetEntityCoords(curVeh)
        ParkVehicle(curVeh, parkingName or CurrentGarage, coords)
    else
        lib.notify({ description = Lang:t("error.no_vehicle"), type = 'error', duration = 5000 })
    end
end)

RegisterNetEvent('qb-garages:client:TakeOutDepot', function(data)
    local vehicle = data.vehicle
    -- check whether the vehicle is already spawned
    local vehExists = DoesEntityExist(OutsideVehicles[vehicle.plate]) or
            (not Config.SpawnVehiclesServerside and GetVehicleByPlate(vehicle.plate))
    if not vehExists then
        local PlayerData = QBCore.Functions.GetPlayerData()
        if PlayerData.money['cash'] >= vehicle.depotprice or PlayerData.money['bank'] >= vehicle.depotprice then
            TriggerEvent("qb-garages:client:TakeOutGarage", data, function(veh)
                if veh then
                    TriggerServerEvent("qb-garage:server:PayDepotPrice", data)
                end
            end)
        else
            lib.notify({ description = Lang:t("error.not_enough"), type = 'error', duration = 5000 })
        end
    else
        lib.notify({ description = Lang:t("error.not_impound"), type = 'error', duration = 5000 })
    end
end)

RegisterNetEvent('qb-garages:client:OpenHouseGarage', function()
    MenuHouseGarage()
end)

RegisterNetEvent('qb-garages:client:setHouseGarage', function(house, hasKey)
    if hasKey then
        if Config.HouseGarages[house] and Config.HouseGarages[house].takeVehicle.x then
            RegisterHousePoly(house)
        end
    else
        RemoveHousePoly(house)
    end
end)

RegisterNetEvent('qb-garages:client:houseGarageConfig', function(garageConfig)
    for _, v in pairs(garageConfig) do
        v.vehicleCategories = Config.HouseGarageCategories
    end
    Config.HouseGarages = garageConfig
    HouseGarages = garageConfig
end)

RegisterNetEvent('qb-garages:client:addHouseGarage', function(house, garageInfo)
    garageInfo.vehicleCategories = Config.HouseGarageCategories
    Config.HouseGarages[house] = garageInfo
    HouseGarages[house] = garageInfo
end)

RegisterNetEvent('qb-garages:client:removeHouseGarage', function(house)
    Config.HouseGarages[house] = nil
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    PlayerGang = PlayerData.gang
    PlayerJob = PlayerData.job

    if not PlayerData then return end

    OutsideVehicles = lib.callback.await('qb-garage:server:GetOutsideVehicles', false)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() and QBCore.Functions.GetPlayerData() ~= {} then
        PlayerData = QBCore.Functions.GetPlayerData()
        if not PlayerData then return end
        PlayerGang = PlayerData.gang
        PlayerJob = PlayerData.job
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        RemoveRadialOptions()
        for k, _ in pairs(GarageZones) do
            exports['qb-target']:RemoveZone(k)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    PlayerGang = gang
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerJob = job
end)

-- Threads
CreateThread(function()
    for _, garage in pairs(Config.Garages) do
        if garage.showBlip then
            local Garage = AddBlipForCoord(garage.blipcoords.x, garage.blipcoords.y, garage.blipcoords.z)
            local blipColor = garage.blipColor ~= nil and garage.blipColor or 3
            SetBlipSprite(Garage, garage.blipNumber)
            SetBlipDisplay(Garage, 4)
            SetBlipScale(Garage, 0.60)
            SetBlipAsShortRange(Garage, true)
            SetBlipColour(Garage, blipColor)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(Config.GarageNameAsBlipName and garage.label or garage.blipName)
            EndTextCommandSetBlipName(Garage)
        end
    end
end)

CreateThread(function()
    for garageName, garage in pairs(Config.Garages) do
        if (garage.type == 'public' or garage.type == 'depot' or garage.type == 'job' or garage.type == 'gang') then
            local zone = {}
            for _, value in pairs(garage.Zone.Shape) do
                zone[#zone + 1] = vector3(value.x, value.y, garage.Zone['minZ'] + 1)
            end
            GarageZones[garageName] = lib.zones.poly({
                points    = zone,
                thickness = garage.Zone.minZ - garage.Zone.maxZ,
                debug     = false,
                onEnter   = function()
                    if IsAuthorizedToAccessGarage(garageName) then
                        UpdateRadialMenu(garageName)
                        lib.showTextUI(Garages[CurrentGarage]['drawText'], {
                            position  = Config.DrawTextPosition,
                            icon      = { 'fas', 'square-parking' },
                            iconColor = '#0096FF'
                        })
                    end
                end,
                inside    = function(self)
                    while self.insideZone do
                        Wait(2500)
                        if self.insideZone then
                            UpdateRadialMenu(garageName)
                        end
                    end
                end,
                onExit    = function()
                    ResetCurrentGarage()
                    RemoveRadialOptions()
                    if lib.isTextUIOpen() then
                        lib.hideTextUI()
                    end
                end
            })
        end
    end
end)

CreateThread(function()
    local debug = false
    for _, garage in pairs(Config.Garages) do
        if garage.debug then
            debug = true
            break
        end
    end
    while debug do
        for _, garage in pairs(Config.Garages) do
            local parkingSpots = garage.ParkingSpots and garage.ParkingSpots or {}
            if next(parkingSpots) and garage.debug then
                for _, location in pairs(parkingSpots) do
                    DrawMarker(2, location.x, location.y, location.z + 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.2, 255, 255, 255, 255, false, false, 0, true, '', '', false)
                end
            end
        end
        Wait(0)
    end
end)

CreateThread(function()
    for category, classes in pairs(Config.VehicleCategories) do
        for _, class in pairs(classes) do
            VehicleClassMap[class] = VehicleClassMap[class] or {}
            VehicleClassMap[class][#VehicleClassMap[class] + 1] = category
        end
    end
end)
