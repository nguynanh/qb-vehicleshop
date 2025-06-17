-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local financetimer = {}
local MAX_VEHICLE_STOCK = 20
-- [BẮT ĐẦU] Cấu hình giá động
-- Giá xe sẽ tăng theo phần trăm sau mỗi lần bán.
-- Ví dụ: 0.10 có nghĩa là tăng 10%
local PriceIncreasePercentage = 0.10 
-- [KẾT THÚC] Cấu hình giá động

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

QBCore.Functions.CreateCallback('qb-vehicleshop:server:spawnvehicle', function(source, cb, plate, vehicle, coords)
    local vehType = QBCore.Shared.Vehicles[vehicle] and QBCore.Shared.Vehicles[vehicle].type or GetVehicleTypeByModel(vehicle)
    local veh = CreateVehicleServerSetter(GetHashKey(vehicle), vehType, coords.x, coords.y, coords.z, coords.w)
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

-- Sync vehicle for other players
RegisterNetEvent('qb-vehicleshop:server:swapVehicle', function(data)
    local src = source
    TriggerClientEvent('qb-vehicleshop:client:swapVehicle', -1, data)
    Wait(1500)                                                -- let new car spawn
    TriggerClientEvent('qb-vehicleshop:client:homeMenu', src) -- reopen main menu
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
-- Thêm vào cuối tệp server.lua
QBCore.Functions.CreateCallback('qb-vehicleshop:server:getDynamicPrice', function(source, cb, vehicleModel)
    local stock = MySQL.scalar.await('SELECT sold_count FROM vehicle_stock WHERE model = ?', { vehicleModel })
    if not stock then
        stock = 0
    end
    local basePrice = QBCore.Shared.Vehicles[vehicleModel]['price']
    if not basePrice then
        cb(nil) -- Trả về nil nếu không tìm thấy xe
        return
    end
    -- Tính giá động giống như khi mua xe
    local dynamicPrice = basePrice * ((1 + PriceIncreasePercentage) ^ stock)
    cb(round(dynamicPrice))
end)