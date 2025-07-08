-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local financetimer = {}
local MAX_VEHICLE_STOCK = 20
-- [BẮT ĐẦU] Cấu hình giá động
-- Giá xe sẽ tăng theo phần trăm sau mỗi lần bán.
-- Ví dụ: 0.10 có nghĩa là tăng 10%
local PriceIncreasePercentage = 0.10 
local MAX_VIP_VEHICLE_STOCK = 5       -- Giới hạn số lượng xe VIP là 5
local VipPriceIncreasePercentage = 0.20 -- Tỷ lệ tăng giá 20% cho xe VIP

local vehicleTypes = { -- https://docs.fivem.net/natives/?_0xA273060E
    motorcycles = 'bike',
    boats = 'boat',
    helicopters = 'heli',
    planes = 'plane',
    submarines = 'submarine',
    trailer = 'trailer',
    train = 'train'
}

local function GetVehicleTypeByModel(model)
    local vehicleData = QBCore.Shared.Vehicles[model]
    if not vehicleData then return 'automobile' end
    local category = vehicleData.category
    local vehicleType = vehicleTypes[category]
    return vehicleType or 'automobile'
end

-- Thay thế hàm cũ bằng phiên bản đã được sửa lỗi này
QBCore.Functions.CreateCallback('qb-vehicleshop:server:spawnvehicle', function(source, cb, plate, vehicle, coords)
    local vehType = QBCore.Shared.Vehicles[vehicle] and QBCore.Shared.Vehicles[vehicle].type or GetVehicleTypeByModel(vehicle)
    local veh = CreateVehicleServerSetter(GetHashKey(vehicle), vehType, coords.x, coords.y, coords.z, coords.w)

    -- Thêm bước kiểm tra xem xe có tồn tại không
    if not DoesEntityExist(veh) then
        print(('^1[qb-vehicleshop] Lỗi: Không thể tạo xe model: %s^7'):format(vehicle))
        cb(nil, nil, nil) -- Trả về nil để tránh lỗi ở client
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetVehicleNumberPlateText(veh, plate)
    local vehProps = {}
    local result = MySQL.rawExecute.await('SELECT mods FROM player_vehicles WHERE plate = ?', { plate })
    if result and result[1] then vehProps = json.decode(result[1].mods) end
    cb(netId, vehProps, plate)
end)

-- Functions
local function round(x)
    return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end

local function calculateFinance(vehiclePrice, downPayment, paymentamount)
    local balance = vehiclePrice - downPayment
    local vehPaymentAmount = balance / paymentamount
    return round(balance), round(vehPaymentAmount)
end

local function calculateNewFinance(paymentAmount, vehData)
    local newBalance = tonumber(vehData.balance - paymentAmount)
    local minusPayment = vehData.paymentsLeft - 1
    local newPaymentsLeft = newBalance / minusPayment
    local newPayment = newBalance / newPaymentsLeft
    return round(newBalance), round(newPayment), newPaymentsLeft
end

local function GeneratePlate()
    local plate = QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(2)
    local result = MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ?', { plate })
    if result then
        return GeneratePlate()
    else
        return plate:upper()
    end
end

local function comma_value(amount)
    local formatted = amount
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if (k == 0) then
            break
        end
    end
    return formatted
end

-- Callbacks
QBCore.Functions.CreateCallback('qb-vehicleshop:server:getVehicles', function(source, cb)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if player then
        local vehicles = MySQL.query.await('SELECT * FROM player_vehicles WHERE citizenid = ?', { player.PlayerData.citizenid })
        if vehicles[1] then
            cb(vehicles)
        end
    end
end)

-- Events

-- Brute force vehicle deletion
RegisterNetEvent('qb-vehicleshop:server:deleteVehicle', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    DeleteEntity(vehicle)
end)


-- Send customer for test drive
RegisterNetEvent('qb-vehicleshop:server:customTestDrive', function(vehicle, playerid)
    local src = source
    local target = tonumber(playerid)
    if not QBCore.Functions.GetPlayer(target) then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.Invalid_ID'), 'error')
        return
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) < 3 then
        TriggerClientEvent('qb-vehicleshop:client:customTestDrive', target, vehicle)
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.playertoofar'), 'error')
    end
end)


-- Buy public vehicle outright
-- SỰ KIỆN NÀY ĐÃ ĐƯỢC CẬP NHẬT ĐỂ TÍNH GIÁ THEO TỶ LỆ PHẦN TRĂM
RegisterNetEvent('qb-vehicleshop:server:buyShowroomVehicle', function(vehicle)
    local src = source
    vehicle = vehicle.buyVehicle
    local pData = QBCore.Functions.GetPlayer(src)
    local cid = pData.PlayerData.citizenid
    local cash = pData.PlayerData.money['cash']
    local bank = pData.PlayerData.money['bank']
    
    -- [BẮT ĐẦU] Logic kiểm tra số lượng và tính giá động
    local stock = MySQL.scalar.await('SELECT sold_count FROM vehicle_stock WHERE model = ?', { vehicle })
    if not stock then
        stock = 0 -- Nếu xe chưa có trong bảng, coi như đã bán 0 chiếc
    end

    if stock >= MAX_VEHICLE_STOCK then
        TriggerClientEvent('QBCore:Notify', src, 'Mẫu xe này đã hết hàng!', 'error')
        return
    end
    
    local basePrice = QBCore.Shared.Vehicles[vehicle]['price']
    -- TÍNH TOÁN GIÁ MỚI THEO CÔNG THỨC LŨY THỪA
    local dynamicPrice = basePrice * ((1 + PriceIncreasePercentage) ^ stock)
    dynamicPrice = round(dynamicPrice) -- Làm tròn giá cuối cùng
    local plate = GeneratePlate()
    -- [KẾT THÚC] Logic kiểm tra số lượng và tính giá động

    local function completePurchase()
        MySQL.insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
            pData.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            'pillboxgarage',
            0
        })
        -- Cập nhật số lượng đã bán
        MySQL.execute('INSERT INTO vehicle_stock (model, sold_count) VALUES (?, 1) ON DUPLICATE KEY UPDATE sold_count = sold_count + 1', { vehicle })
        
        TriggerClientEvent('QBCore:Notify', src, 'Chúc mừng bạn đã mua xe với giá $'..comma_value(dynamicPrice), 'success')
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
    end

    if cash >= dynamicPrice then
        pData.Functions.RemoveMoney('cash', dynamicPrice, 'vehicle-bought-in-showroom')
        completePurchase()
    elseif bank >= dynamicPrice then
        pData.Functions.RemoveMoney('bank', dynamicPrice, 'vehicle-bought-in-showroom')
        completePurchase()
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)


-- Transfer vehicle to player in passenger seat
QBCore.Commands.Add('transfervehicle', Lang:t('general.command_transfervehicle'), { { name = 'ID', help = Lang:t('general.command_transfervehicle_help') }, { name = 'amount', help = Lang:t('general.command_transfervehicle_amount') } }, false, function(source, args)
    local src = source
    local buyerId = tonumber(args[1])
    local sellAmount = tonumber(args[2])
    if buyerId == 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.Invalid_ID'), 'error') end
    local ped = GetPlayerPed(src)
    local targetPed = GetPlayerPed(buyerId)
    if targetPed == 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.buyerinfo'), 'error') end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notinveh'), 'error') end
    local plate = QBCore.Shared.Trim(GetVehicleNumberPlateText(vehicle))
    if not plate then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.vehinfo'), 'error') end
    local player = QBCore.Functions.GetPlayer(src)
    local target = QBCore.Functions.GetPlayer(buyerId)
    local row = MySQL.single.await('SELECT * FROM player_vehicles WHERE plate = ?', { plate })
    if Config.PreventFinanceSelling then
        if row.balance > 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.financed'), 'error') end
    end
    if row.citizenid ~= player.PlayerData.citizenid then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notown'), 'error') end
    if #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > 5.0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.playertoofar'), 'error') end
    local targetcid = target.PlayerData.citizenid
    local targetlicense = QBCore.Functions.GetIdentifier(target.PlayerData.source, 'license')
    if not target then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.buyerinfo'), 'error') end
    if not sellAmount then
        MySQL.update('UPDATE player_vehicles SET citizenid = ?, license = ? WHERE plate = ?', { targetcid, targetlicense, plate })
        TriggerClientEvent('QBCore:Notify', src, Lang:t('success.gifted'), 'success')
        TriggerClientEvent('vehiclekeys:client:SetOwner', buyerId, plate)
        TriggerClientEvent('QBCore:Notify', buyerId, Lang:t('success.received_gift'), 'success')
        return
    end
    if target.Functions.GetMoney('cash') > sellAmount then
        MySQL.update('UPDATE player_vehicles SET citizenid = ?, license = ? WHERE plate = ?', { targetcid, targetlicense, plate })
        player.Functions.AddMoney('cash', sellAmount, 'transferred vehicle')
        target.Functions.RemoveMoney('cash', sellAmount, 'transferred vehicle')
        TriggerClientEvent('QBCore:Notify', src, Lang:t('success.soldfor') .. comma_value(sellAmount), 'success')
        TriggerClientEvent('vehiclekeys:client:SetOwner', buyerId, plate)
        TriggerClientEvent('QBCore:Notify', buyerId, Lang:t('success.boughtfor') .. comma_value(sellAmount), 'success')
    elseif target.Functions.GetMoney('bank') > sellAmount then
        MySQL.update('UPDATE player_vehicles SET citizenid = ?, license = ? WHERE plate = ?', { targetcid, targetlicense, plate })
        player.Functions.AddMoney('bank', sellAmount, 'transferred vehicle')
        target.Functions.RemoveMoney('bank', sellAmount, 'transferred vehicle')
        TriggerClientEvent('QBCore:Notify', src, Lang:t('success.soldfor') .. comma_value(sellAmount), 'success')
        TriggerClientEvent('vehiclekeys:client:SetOwner', buyerId, plate)
        TriggerClientEvent('QBCore:Notify', buyerId, Lang:t('success.boughtfor') .. comma_value(sellAmount), 'success')
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.buyertoopoor'), 'error')
    end
end)

QBCore.Functions.CreateCallback('qb-vehicleshop:server:getDynamicPrice', function(source, cb, vehicleModel)
    local sold_count = MySQL.scalar.await('SELECT sold_count FROM vehicle_stock WHERE model = ?', { vehicleModel })
    if not sold_count then
        sold_count = 0
    end

    local vehicleData = QBCore.Shared.Vehicles[vehicleModel]
    if not vehicleData then
        cb(nil)
        return
    end

    local isVipCar = (vehicleData.shop == 'vip')

    -- Sử dụng đúng tỷ lệ tăng giá
    local increasePercentage = isVipCar and VipPriceIncreasePercentage or PriceIncreasePercentage
    local dynamicPrice = vehicleData['price'] * ((1 + increasePercentage) ^ sold_count)

    -- Sử dụng đúng giới hạn số lượng (stock)
    local maxStock = isVipCar and MAX_VIP_VEHICLE_STOCK or MAX_VEHICLE_STOCK
    local remaining_stock = maxStock - sold_count
    if remaining_stock < 0 then remaining_stock = 0 end

    -- Trả về cho client giá, số lượng còn lại, và cả số lượng tối đa
    cb({
        price = round(dynamicPrice),
        stock = remaining_stock,
        maxStock = maxStock
    })
end)

-- [BẮT ĐẦU] Logic tự động thay đổi và lưu trạng thái xe trưng bày
local ShowroomState = {}

local function SaveShowroomState()
    if next(ShowroomState) == nil then return end
    local jsonState = json.encode(ShowroomState)
    SaveResourceFile(GetCurrentResourceName(), 'showroom_state.json', jsonState, -1)
end

local function LoadShowroomState()
    local jsonState = LoadResourceFile(GetCurrentResourceName(), 'showroom_state.json')
    if jsonState then
        local success, data = pcall(json.decode, jsonState)
        if success and data and next(data) then
            ShowroomState = data
            return true
        end
    end
    return false
end

local function GetVehiclesForShop(shopName)
    local shopVehicles = {}
    local stockCounts = MySQL.query.await('SELECT model, sold_count FROM vehicle_stock', {})
    local stockMap = {}
    for _, row in ipairs(stockCounts) do
        stockMap[row.model] = row.sold_count
    end
    for model, data in pairs(QBCore.Shared.Vehicles) do
        local sold_count = stockMap[model] or 0
        if sold_count < MAX_VEHICLE_STOCK then
            local isSoldInShop = false
            if type(data.shop) == 'table' then
                for _, shop in pairs(data.shop) do
                    if shop == shopName then
                        isSoldInShop = true
                        break
                    end
                end
            elseif data.shop == shopName then
                isSoldInShop = true
            end
            if isSoldInShop then
                table.insert(shopVehicles, model)
            end
        end
    end
    return shopVehicles
end

local function GetVipVehicles()
    local vipVehicles = {}
    local stockCounts = MySQL.query.await('SELECT model, sold_count FROM vehicle_stock', {})
    local stockMap = {}
    for _, row in ipairs(stockCounts) do
        stockMap[row.model] = row.sold_count
    end
    for model, data in pairs(QBCore.Shared.Vehicles) do
        local sold_count = stockMap[model] or 0
        if sold_count < MAX_VEHICLE_STOCK and data.shop and data.shop == 'vip' then
            table.insert(vipVehicles, model)
        end
    end
    return vipVehicles
end

local function RotateShowroomVehicles()
    local vipVehicleList = GetVipVehicles()

    for shopName, shopData in pairs(Config.Shops) do
        if shopData.enabled then
            local tempRegularVehicleList = GetVehiclesForShop(shopName)
            if #tempRegularVehicleList > 0 or #vipVehicleList > 0 then
                if not ShowroomState[shopName] then ShowroomState[shopName] = {} end
                for slotId, slotData in pairs(shopData.ShowroomVehicles) do
                    local vehicleModel = nil
                    
                    if slotData.isVip and #vipVehicleList > 0 then
                        local randomIndex = math.random(#vipVehicleList)
                        vehicleModel = vipVehicleList[randomIndex]
                    elseif not slotData.isVip and #tempRegularVehicleList > 0 then
                        local randomIndex = math.random(#tempRegularVehicleList)
                        vehicleModel = tempRegularVehicleList[randomIndex]
                        table.remove(tempRegularVehicleList, randomIndex)
                    end

                    if vehicleModel then
                        ShowroomState[shopName][slotId] = vehicleModel
                        local isVip = slotData.isVip or false
                        TriggerClientEvent('qb-vehicleshop:client:autoSwapVehicle', -1, shopName, slotId, vehicleModel, isVip)
                        Wait(500)
                    end
                end
            end
        end
    end
    SaveShowroomState()
end

RegisterNetEvent('qb-vehicleshop:server:clientReadyForState', function()
    local src = source
    if ShowroomState and next(ShowroomState) then
        for shopName, slots in pairs(ShowroomState) do
            if Config.Shops[shopName] and Config.Shops[shopName].enabled then
                for slotId, vehicleModel in pairs(slots) do
                    if vehicleModel then
                        local isVip = Config.Shops[shopName].ShowroomVehicles[slotId].isVip or false
                        TriggerClientEvent('qb-vehicleshop:client:autoSwapVehicle', src, shopName, slotId, vehicleModel, isVip)
                        Wait(200)
                    end
                end
            end
        end
    end
end)

-- [[BẮT ĐẦU] Logic phục hồi và xoay vòng xe (PHIÊN BẢN SỬA LỖI CUỐI CÙNG)]]

-- Tải trạng thái đã lưu ngay khi script bắt đầu
if not LoadShowroomState() then
    -- Nếu không có tệp trạng thái, tạo một luồng riêng biệt và chờ một chút
    -- trước khi xoay vòng xe lần đầu tiên để client kịp sẵn sàng.
    CreateThread(function()
        print('[qb-vehicleshop] Khong tim thay trang thai da luu, se xoay vong xe lan dau sau 20 giay.')
        Wait(20000)
        RotateShowroomVehicles()
    end)
end

-- Hàm tính toán số giây cho đến 2 giờ sáng tiếp theo
local function GetSecondsUntilTwoAM()
    local now = os.date('*t')
    local target = { year = now.year, month = now.month, day = now.day, hour = 2, min = 0, sec = 0 }
    local timeNow = os.time(now)
    local timeTarget = os.time(target)
    if timeNow >= timeTarget then
        timeTarget = timeTarget + (24 * 60 * 60)
    end
    return timeTarget - timeNow
end

-- Vòng lặp hẹn giờ chính để tự động xoay vòng xe
CreateThread(function()
    if not Config.EnableAutoRotation then
        print('[qb-vehicleshop] Tu dong doi xe da duoc tat trong config.')
        return
    end

    -- Chờ một chút để tránh xung đột lúc khởi động
    Wait(5000)

    if Config.RotationMode == 'daily' then
        print('[qb-vehicleshop] Che do doi xe: Hang ngay @ 2:00 AM.')
        while true do
            local secondsToWait = GetSecondsUntilTwoAM()
            print(('[qb-vehicleshop] Lan doi xe tiep theo sau %d giay.'):format(secondsToWait))
            Wait(secondsToWait * 1000)
            print('[qb-vehicleshop] Da den 2:00 sang! Bat dau thay doi xe.')
            RotateShowroomVehicles()
            Wait(60000)
        end
    elseif Config.RotationMode == 'interval' then
        local intervalMinutes = Config.RotationIntervalMinutes or 30
        local waitMs = intervalMinutes * 60 * 1000
        print(('[qb-vehicleshop] Che do doi xe: Moi %s phut.'):format(intervalMinutes))
        while true do
            Wait(waitMs)
            print(('[qb-vehicleshop] Da het %s phut! Bat dau thay doi xe.'):format(intervalMinutes))
            RotateShowroomVehicles()
        end
    end
end)

-- [KẾT THÚC] Logic phục hồi và xoay vòng xe

-- Exports for other scripts
exports('GetShowroomState', function()
    return ShowroomState
end)

exports('getVehiclePrice', function(vehicleModel)
    local sold_count = MySQL.scalar.await('SELECT sold_count FROM vehicle_stock WHERE model = ?', { vehicleModel })
    if not sold_count then
        sold_count = 0
    end
    local basePrice = QBCore.Shared.Vehicles[vehicleModel] and QBCore.Shared.Vehicles[vehicleModel]['price']
    if not basePrice then
        return nil
    end
    local dynamicPrice = basePrice * ((1 + PriceIncreasePercentage) ^ sold_count)
    return round(dynamicPrice)
end)

exports('GetShowroomConfig', function()
    return Config.Shops
end)