return {
	isSeatbeltOn = function()
		if GetResourceState('jim-mechanic') == 'started' then
			return exports['jim-mechanic']:seatBeltOn()
		else
			return LocalPlayer.state.isSeatbeltOn or false -- Adjust based on your framework
		end
	end,
	getVehicleFuel = function(currentVehicle)
		if GetResourceState('cdn-fuel') == 'started' then
			return exports['cdn-fuel']:GetFuel(currentVehicle)
		elseif GetResourceState('cdn-fuel') == 'started' then
			return exports['cdn-fuel']:GetFuel(currentVehicle)
		elseif GetResourceState('cdn-fuel') == 'started' then
			return exports['cdn-fuel']:GetFuel(currentVehicle)
		elseif GetResourceState('ox_fuel') == 'started' then
			return Entity(currentVehicle).state.fuel
		else
			return GetVehicleFuelLevel(currentVehicle)
		end
	end,
	getNosLevel = function(currentVehicle) -- Replace this with your own logic to grab the nos level of the vehicle.
		return 0
	end,
}
