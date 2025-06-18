-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()
local testDriveZone = nil
local vehicleMenu = {}
local Initialized = false
local testDriveVeh, inTestDrive = 0, false
local ClosestVehicle = 1
local zones = {}
local insideShop, tempShop = nil, nil

-- Handlers
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    local citizenid = PlayerData.citizenid
    if not Initialized then Init() end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end
    if next(PlayerData) ~= nil and not Initialized then
        PlayerData = QBCore.Functions.GetPlayerData()
        local citizenid = PlayerData.citizenid
        Init()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    local citizenid = PlayerData.citizenid
    TriggerServerEvent('qb-vehicleshop:server:removePlayer', citizenid)
    PlayerData = {}
end)

local function CheckPlate(vehicle, plateToSet)
    local vehiclePlate = promise.new()
    CreateThread(function()
        while true do
            Wait(500)
            if GetVehicleNumberPlateText(vehicle) == plateToSet then
                vehiclePlate:resolve(true)
                return
            else
                SetVehicleNumberPlateText(vehicle, plateToSet)
            end
        end
    end)
    return vehiclePlate
end

-- Static Headers
local vehHeaderMenu = {
    {
        header = Lang:t('menus.vehHeader_header'),
        txt = Lang:t('menus.vehHeader_txt'),
        icon = 'fa-solid fa-car',
        params = {
            event = 'qb-vehicleshop:client:showVehOptions'
        }
    }
}

local financeMenu = {
    {
        header = Lang:t('menus.financed_header'),
        txt = Lang:t('menus.finance_txt'),
        icon = 'fa-solid fa-user-ninja',
        params = {
            event = 'qb-vehicleshop:client:getVehicles'
        }
    }
}

local returnTestDrive = {
    {
        header = Lang:t('menus.returnTestDrive_header'),
        icon = 'fa-solid fa-flag-checkered',
        params = {
            event = 'qb-vehicleshop:client:TestDriveReturn'
        }
    }
}

-- Functions
local function drawTxt(text, font, x, y, scale, r, g, b, a)
    SetTextFont(font)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextCentre(1)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function tablelength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

local function comma_value(amount)
    local formatted = amount
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

local function getVehName()
    return QBCore.Shared.Vehicles[Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle]['name']
end

local function getVehPrice()
    return comma_value(QBCore.Shared.Vehicles[Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle]['price'])
end

local function getVehBrand()
    return QBCore.Shared.Vehicles[Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle]['brand']
end

-- DÁN ĐOẠN MÃ ĐÚNG NÀY VÀO
local function setClosestShowroomVehicle()
    local pos = GetEntityCoords(PlayerPedId(), true)
    local current = nil
    local dist = nil
    local closestShop = insideShop

    -- Dòng kiểm tra này sẽ ngăn lỗi xảy ra
    if not closestShop or not Config.Shops[closestShop] then
        return
    end

    for id in pairs(Config.Shops[closestShop]['ShowroomVehicles']) do
        local dist2 = #(pos - vector3(Config.Shops[closestShop]['ShowroomVehicles'][id].coords.x, Config.Shops[closestShop]['ShowroomVehicles'][id].coords.y, Config.Shops[closestShop]['ShowroomVehicles'][id].coords.z))
        if current then
            if dist2 < dist then
                current = id
                dist = dist2
            end
        else
            dist = dist2
            current = id
        end
    end
    if current ~= ClosestVehicle then
        ClosestVehicle = current
    end
end

local function createTestDriveReturn()
    testDriveZone = BoxZone:Create(
        Config.Shops[insideShop]['ReturnLocation'],
        3.0,
        5.0,
        {
            name = 'box_zone_testdrive_return_' .. insideShop,
        })

    testDriveZone:onPlayerInOut(function(isPointInside)
        if isPointInside and IsPedInAnyVehicle(PlayerPedId()) then
            SetVehicleForwardSpeed(GetVehiclePedIsIn(PlayerPedId(), false), 0)
            exports['qb-menu']:openMenu(returnTestDrive)
        else
            exports['qb-menu']:closeMenu()
        end
    end)
end

local function startTestDriveTimer(testDriveTime, prevCoords)
    local gameTimer = GetGameTimer()
    CreateThread(function()
        Wait(2000) -- Avoids the condition to run before entering vehicle
        while inTestDrive do
            if GetGameTimer() < gameTimer + tonumber(1000 * testDriveTime) then
                local secondsLeft = GetGameTimer() - gameTimer
                if secondsLeft >= tonumber(1000 * testDriveTime) - 20 or GetPedInVehicleSeat(NetToVeh(testDriveVeh), -1) ~= PlayerPedId() then
                    TriggerServerEvent('qb-vehicleshop:server:deleteVehicle', testDriveVeh)
                    testDriveVeh = 0
                    inTestDrive = false
                    SetEntityCoords(PlayerPedId(), prevCoords)
                    QBCore.Functions.Notify(Lang:t('general.testdrive_complete'))
                end
                drawTxt(Lang:t('general.testdrive_timer') .. math.ceil(testDriveTime - secondsLeft / 1000), 4, 0.5, 0.93, 0.50, 255, 255, 255, 180)
            end
            Wait(0)
        end
    end)
end

local function createVehZones(shopName, entity)
    if not Config.UsingTarget then
        for i = 1, #Config.Shops[shopName]['ShowroomVehicles'] do
            zones[#zones + 1] = BoxZone:Create(
                vector3(Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].x,
                    Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].y,
                    Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].z),
                Config.Shops[shopName]['Zone']['size'],
                Config.Shops[shopName]['Zone']['size'],
                {
                    name = 'box_zone_' .. shopName .. '_' .. i,
                    minZ = Config.Shops[shopName]['Zone']['minZ'],
                    maxZ = Config.Shops[shopName]['Zone']['maxZ'],
                    debugPoly = false,
                })
        end
        local combo = ComboZone:Create(zones, { name = 'vehCombo', debugPoly = false })
        combo:onPlayerInOut(function(isPointInside)
            if isPointInside then
                if PlayerData and PlayerData.job and (PlayerData.job.name == Config.Shops[insideShop]['Job'] or Config.Shops[insideShop]['Job'] == 'none') then
                    exports['qb-menu']:showHeader(vehHeaderMenu)
                end
            else
                exports['qb-menu']:closeMenu()
            end
        end)
    else
        exports['qb-target']:AddTargetEntity(entity, {
            options = {
                {
                    type = 'client',
                    event = 'qb-vehicleshop:client:showVehOptions',
                    icon = 'fas fa-car',
                    label = Lang:t('general.vehinteraction'),
                    canInteract = function()
                        local closestShop = insideShop
                        return closestShop and (Config.Shops[closestShop]['Job'] == 'none' or PlayerData.job.name == Config.Shops[closestShop]['Job'])
                    end
                },
            },
            distance = 3.0
        })
    end
end

-- Zones
-- Thay thế hàm này trong client.lua
-- DÁN TOÀN BỘ ĐOẠN MÃ NÀY VÀO FILE CỦA BẠN --

local function createFreeUseShop(shopShape, name)
    local zone = PolyZone:Create(shopShape, {
        name = name,
        minZ = shopShape.minZ,
        maxZ = shopShape.maxZ,
    })

    zone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            insideShop = name
            CreateThread(function()
                while insideShop == name do -- Thay đổi: Chỉ chạy khi còn ở trong đúng shop này
                    Wait(500)
                    setClosestShowroomVehicle()

                    if Config.Shops[insideShop] and Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle] then
                        local currentVehicleModel = Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle
                        if currentVehicleModel and QBCore.Shared.Vehicles[currentVehicleModel] then
                            QBCore.Functions.TriggerCallback('qb-vehicleshop:server:getDynamicPrice', function(data)
                                if not insideShop or not data or not QBCore.Shared.Vehicles[currentVehicleModel] then return end
                                local brand = QBCore.Shared.Vehicles[currentVehicleModel]['brand']
                                local vehName = QBCore.Shared.Vehicles[currentVehicleModel]['name']
                                local stockMessage = ' | Kho: ' .. data.stock .. '/' .. 20 -- Thêm chuỗi hiển thị số lượng
                                vehicleMenu = {
                                    {
                                        isMenuHeader = true,
                                        icon = 'fa-solid fa-circle-info',
                                        header = brand:upper() .. ' ' .. vehName:upper() .. ' - Giá: $' .. comma_value(data.price) .. stockMessage,
                                    },
                                    {
                                        header = Lang:t('menus.test_header'),
                                        txt = Lang:t('menus.freeuse_test_txt'),
                                        icon = 'fa-solid fa-car-on',
                                        params = { event = 'qb-vehicleshop:client:TestDrive' }
                                    },
                                    {
                                        header = Lang:t('menus.freeuse_buy_header'),
                                        txt = Lang:t('menus.freeuse_buy_txt'),
                                        icon = 'fa-solid fa-hand-holding-dollar',
                                        params = {
                                            event = 'qb-vehicleshop:client:confirmPurchase',
                                            args = { vehicleModel = currentVehicleModel }
                                        }
                                    },
                                }
                            end, currentVehicleModel)
                        end
                    end
                end
            end)
        else
            if insideShop == name then -- Chỉ reset khi rời khỏi đúng shop này
                insideShop = nil
                ClosestVehicle = 1
            end
        end
    end)
end

-- Thay thế toàn bộ hàm Init() cũ bằng hàm mới này
-- Thay thế toàn bộ hàm Init() cũ bằng hàm mới này
function Init()
    Initialized = true
    CreateThread(function()
        while QBCore.Shared.Vehicles == nil or next(QBCore.Shared.Vehicles) == nil do
            Wait(500)
        end

        -- Tạo Zone cho các cửa hàng được bật
        for name, shop in pairs(Config.Shops) do
            if shop.enabled then
                if shop['Type'] == 'free-use' then
                    createFreeUseShop(shop['Zone']['Shape'], name)
                end
            end
        end

        -- Tạo xe trưng bày cho các cửa hàng được bật
        for k, shopData in pairs(Config.Shops) do
            if shopData.enabled then
                for i = 1, #shopData.ShowroomVehicles do
                    local vehicleInfo = shopData.ShowroomVehicles[i]
                    local modelName = vehicleInfo.defaultVehicle
                    local modelHash = GetHashKey(modelName)
                    if modelHash ~= 0 then
                        RequestModel(modelHash)
                        local timeout = 5000
                        local startTime = GetGameTimer()
                        while not HasModelLoaded(modelHash) and (GetGameTimer() - startTime) < timeout do
                            Wait(50)
                        end
                        if HasModelLoaded(modelHash) then
                            local veh = CreateVehicle(modelHash, vehicleInfo.coords.x, vehicleInfo.coords.y, vehicleInfo.coords.z, false, false)
                            SetModelAsNoLongerNeeded(modelHash)
                            SetVehicleOnGroundProperly(veh)
                            SetEntityInvincible(veh, true)
                            SetVehicleDirtLevel(veh, 0.0)
                            SetVehicleDoorsLocked(veh, 3)
                            SetEntityHeading(veh, vehicleInfo.coords.w)
                            FreezeEntityPosition(veh, true)
                            SetVehicleNumberPlateText(veh, 'BUY ME')
                            if Config.UsingTarget then createVehZones(k, veh) end
                        else
                            print(('[^1ERROR^7] [VehicleShop Client] Model xe "%s" cho cua hang "%s" khong the tai duoc (timeout).'):format(modelName, k))
                        end
                    else
                        print(('[^1ERROR^7] [VehicleShop Client] Model xe "%s" cho cua hang "%s" KHONG TON TAI.'):format(modelName, k))
                    end
                end
                if not Config.UsingTarget then createVehZones(k) end
            end
        end

        TriggerServerEvent('qb-vehicleshop:server:clientReadyForState')
    end)
end
-- Events
RegisterNetEvent('qb-vehicleshop:client:homeMenu', function()
    exports['qb-menu']:openMenu(vehicleMenu)
end)

RegisterNetEvent('qb-vehicleshop:client:showVehOptions', function()
    exports['qb-menu']:openMenu(vehicleMenu, true, true)
end)

RegisterNetEvent('qb-vehicleshop:client:TestDrive', function()
    if not inTestDrive and ClosestVehicle ~= 0 then
        inTestDrive = true
        local prevCoords = GetEntityCoords(PlayerPedId())
        tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
        QBCore.Functions.TriggerCallback('qb-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
            local timeout = 5000
            local startTime = GetGameTimer()
            while not NetworkDoesNetworkIdExist(netId) do
                Wait(10)
                if GetGameTimer() - startTime > timeout then
                    return
                end
            end
            local veh = NetworkGetEntityFromNetworkId(netId)
            NetworkRequestControlOfEntity(veh)
            SetEntityAsMissionEntity(veh, true, true)
            Citizen.InvokeNative(0xAD738C3085FE7E11, veh, true, true)
            SetVehicleNumberPlateText(veh, vehPlate)
            exports['LegacyFuel']:SetFuel(veh, 100)
            TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            SetVehicleEngineOn(veh, true, true, false)
            testDriveVeh = netId
            QBCore.Functions.Notify(Lang:t('general.testdrive_timenoti', { testdrivetime = Config.Shops[tempShop]['TestDriveTimeLimit'] }), "success")
        end, 'TESTDRIVE', Config.Shops[tempShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle, Config.Shops[tempShop]['TestDriveSpawn'], true) 

        createTestDriveReturn()
        startTestDriveTimer(Config.Shops[tempShop]['TestDriveTimeLimit'] * 60, prevCoords)
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:customTestDrive', function(data)
    if not inTestDrive then
        inTestDrive = true
        local vehicle = data
        local prevCoords = GetEntityCoords(PlayerPedId())
        tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
        QBCore.Functions.TriggerCallback('qb-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
            local timeout = 5000
            local startTime = GetGameTimer()
            while not NetworkDoesNetworkIdExist(netId) do
                Wait(10)
                if GetGameTimer() - startTime > timeout then
                    return
                end
            end
            local veh = NetworkGetEntityFromNetworkId(netId)
            NetworkRequestControlOfEntity(veh)
            SetEntityAsMissionEntity(veh, true, true)
            Citizen.InvokeNative(0xAD738C3085FE7E11, veh, true, true)
            SetVehicleNumberPlateText(veh, vehPlate)
            exports['LegacyFuel']:SetFuel(veh, 100)
            TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            SetVehicleEngineOn(veh, true, true, false)
            testDriveVeh = netId
            QBCore.Functions.Notify(Lang:t('general.testdrive_timenoti', { testdrivetime = Config.Shops[tempShop]['TestDriveTimeLimit'] }))
        end, 'TESTDRIVE', Config.Shops[tempShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle, Config.Shops[tempShop]['TestDriveSpawn'], true) 
        createTestDriveReturn()
        startTestDriveTimer(Config.Shops[tempShop]['TestDriveTimeLimit'] * 60, prevCoords)
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:TestDriveReturn', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped)
    local entity = NetworkGetEntityFromNetworkId(testDriveVeh)
    if veh == entity then
        testDriveVeh = 0
        inTestDrive = false
        DeleteEntity(veh)
        exports['qb-menu']:closeMenu()
        testDriveZone:destroy()
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_return'), 'error')
    end
end)


RegisterNetEvent('qb-vehicleshop:client:buyShowroomVehicle', function(vehicle, plate)
    tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
    QBCore.Functions.TriggerCallback('qb-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
        while not NetworkDoesNetworkIdExist(netId) do Wait(10) end
        local veh = NetworkGetEntityFromNetworkId(netId)
        Citizen.Await(CheckPlate(veh, vehPlate))
        QBCore.Functions.SetVehicleProperties(veh, properties)
        exports['LegacyFuel']:SetFuel(veh, 100)
        TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleEngineOn(veh, true, true, false)
    end, plate, vehicle, Config.Shops[tempShop]['VehicleSpawn'], true)
end)


RegisterNetEvent('qb-vehicleshop:client:openIdMenu', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = QBCore.Shared.Vehicles[data.vehicle]['name'],
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                text = Lang:t('menus.submit_ID'),
                name = 'playerid',
                type = 'number',
                isRequired = true
            }
        }
    })
    if dialog then
        if not dialog.playerid then return end
        if data.type == 'testDrive' then
            TriggerServerEvent('qb-vehicleshop:server:customTestDrive', data.vehicle, dialog.playerid)
        elseif data.type == 'sellVehicle' then
            TriggerServerEvent('qb-vehicleshop:server:sellShowroomVehicle', data.vehicle, dialog.playerid)
        end
    end
end)

-- Threads
CreateThread(function()
    for k, v in pairs(Config.Shops) do
        if v.enabled and v.showBlip then -- Thêm điều kiện v.enabled
            local Dealer = AddBlipForCoord(v.Location)
            SetBlipSprite(Dealer, v.blipSprite)
            SetBlipDisplay(Dealer, 4)
            SetBlipScale(Dealer, 0.70)
            SetBlipAsShortRange(Dealer, true)
            SetBlipColour(Dealer, v.blipColor)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(v.ShopLabel)
            EndTextCommandSetBlipName(Dealer)
        end
    end
end)
-- [BẮT ĐẦU] Logic nhận sự kiện đổi xe tự động (Sửa lỗi qb-target)
RegisterNetEvent('qb-vehicleshop:client:autoSwapVehicle', function(shopName, slotId, newVehicleModel)
    -- Kiểm tra xem cửa hàng và vị trí có tồn tại không
    if not Config.Shops[shopName] or not Config.Shops[shopName]['ShowroomVehicles'][slotId] then return end

    -- Chỉ đổi nếu xe mới khác xe cũ
    if Config.Shops[shopName]['ShowroomVehicles'][slotId].chosenVehicle ~= newVehicleModel then
        local slotCoords = Config.Shops[shopName]['ShowroomVehicles'][slotId].coords
        local closestVehicle, closestDistance = QBCore.Functions.GetClosestVehicle(vector3(slotCoords.x, slotCoords.y, slotCoords.z))

        if closestVehicle ~= 0 and closestDistance < 5.0 then
            -- Đã xóa dòng lệnh gây lỗi 'RemoveEntity' ở đây. Chỉ cần xóa xe là đủ.
            DeleteEntity(closestVehicle)
        end

        Config.Shops[shopName]['ShowroomVehicles'][slotId].chosenVehicle = newVehicleModel
        local modelHash = GetHashKey(newVehicleModel)

        RequestModel(modelHash)
        while not HasModelLoaded(modelHash) do
            Wait(50)
        end

        local newVeh = CreateVehicle(modelHash, slotCoords.x, slotCoords.y, slotCoords.z, false, false)
        SetModelAsNoLongerNeeded(modelHash)
        SetVehicleOnGroundProperly(newVeh)
        SetEntityInvincible(newVeh, true)
        SetEntityHeading(newVeh, slotCoords.w)
        SetVehicleDoorsLocked(newVeh, 3)
        FreezeEntityPosition(newVeh, true)
        SetVehicleNumberPlateText(newVeh, 'BUY ME')

        -- Gắn lại vùng tương tác/target cho xe mới
        if Config.UsingTarget then
            createVehZones(shopName, newVeh)
        end
    end
end)
-- [KẾT THÚC] Logic nhận sự kiện đổi xe tự động (Sửa lỗi qb-target)
RegisterNetEvent('qb-vehicleshop:client:confirmPurchase', function(data)
    local vehicleModel = data.vehicleModel
    local vehicleName = QBCore.Shared.Vehicles[vehicleModel] and QBCore.Shared.Vehicles[vehicleModel]['name'] or 'Xe không rõ'
    local vehiclePrice = QBCore.Shared.Vehicles[vehicleModel] and QBCore.Shared.Vehicles[vehicleModel]['price'] or 'Không rõ'

    exports['qb-menu']:openMenu({
        {
            isMenuHeader = true,
            header = 'Xác nhận giao dịch',
            txt = 'Bạn có muốn mua ' .. vehicleName .. ' không?',
        },
        {
            header = 'Đồng ý',
            txt = 'Giá: $'..tostring(vehiclePrice),
            icon = 'fa-solid fa-check',
            params = {
                isServer = true,
                event = 'qb-vehicleshop:server:buyShowroomVehicle',
                args = {
                    buyVehicle = vehicleModel
                }
            }
        },
        {
            header = 'Từ chối',
            txt = 'Quay lại cửa hàng',
            icon = 'fa-solid fa-xmark',
            params = {
                event = 'qb-vehicleshop:client:homeMenu' -- Quay về menu chính của cửa hàng
            }
        }
    })
end)