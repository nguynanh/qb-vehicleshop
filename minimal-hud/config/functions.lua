return {
	isSeatbeltOn = function()
		if GetResourceState('jim-mechanic') == 'started' then
			return exports['jim-mechanic']:seatBeltOn()
		else
			return LocalPlayer.state.isSeatbeltOn or false -- Adjust based on your framework
		end
	end,
	getVehicleFuel = function(currentVehicle)
		if GetResourceState('ps-fuel') == 'started' then
			return exports['ps-fuel']:GetFuel(currentVehicle)
		elseif GetResourceState('cdn-fuel') == 'started' then
			return exports['cdn-fuel']:GetFuel(currentVehicle)
		elseif GetResourceState('LegacyFuel') == 'started' then
			return exports['LegacyFuel']:GetFuel(currentVehicle)
		elseif GetResourceState('ox_fuel') == 'started' then
			return Entity(currentVehicle).state.fuel
		else
			return GetVehicleFuelLevel(currentVehicle)
		end
	end,
	-- Tệp: minimal-hud/config/functions.lua

	getNosLevel = function(currentVehicle)
  	  if not currentVehicle or currentVehicle == 0 then return 0 end
  	  local plate = GetVehicleNumberPlateText(currentVehicle):match'^%s*(.*%S)' or ''
   	 if exports['qb-mechanicjob'] then
   	     return exports['qb-mechanicjob']:GetNitroLevel(plate)
   	 end
  	  return 0
	end,
}
