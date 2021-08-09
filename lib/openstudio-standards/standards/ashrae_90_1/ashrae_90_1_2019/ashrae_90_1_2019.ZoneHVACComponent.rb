class ASHRAE9012019 < ASHRAE901
  # @!group ZoneHVACComponent

  # Determine if vestibule heating control is required.
  # Required for 90.1-2019 per 6.4.3.9.
  #
  # @ref [References::ASHRAE9012019] 6.4.3.9
  # @return [Bool] returns true if successful, false if not
  def zone_hvac_component_vestibule_heating_control_required?(zone_hvac_component)
    # Ensure that the equipment is assigned to a thermal zone
    if zone_hvac_component.thermalZone.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.ZoneHVACComponent', "For #{zone_hvac_component.name}: equipment is not assigned to a thermal zone, cannot apply vestibule heating control.")
      return false
    end

    # Only applies to equipment that is in vestibule zones
    return true if thermal_zone_vestibule?(zone_hvac_component.thermalZone.get)

    # If here, vestibule heating control not required
    return false
  end

  # Add occupant standby controls to zone equipment
  # Currently, the controls consists of cycling the
  # fan during the occupant standby mode hours
  #
  # @param zone_hvac_component OpenStudio zonal equipment object
  # @retrun [Boolean] true if sucessful, false otherwise
  def zone_hvac_model_standby_mode_occupancy_control(zone_hvac_component)
    # Ensure that the equipment is assigned to a thermal zone
    if zone_hvac_component.thermalZone.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.ZoneHVACComponent', "For #{zone_hvac_component.name}: equipment is not assigned to a thermal zone, cannot apply vestibule heating control.")
      return true
    end

    # Convert this to the actual class type
    zone_hvac = if zone_hvac_component.to_ZoneHVACFourPipeFanCoil.is_initialized
                  zone_hvac_component.to_ZoneHVACFourPipeFanCoil.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalAirConditioner.get
                elsif zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
                  zone_hvac_component.to_ZoneHVACPackagedTerminalHeatPump.get
                end

    # Do nothing for other types of zone HVAC equipment
    if zone_hvac.nil?
      return true
    end

    # Get supply fan
    # Only Fan:OnOff can cycle
    fan = zone_hvac.supplyAirFan
    if fan.to_FanOnOff.is_initialized
      fan = fan.to_FanOnOff.get
    else
      return true
    end

    # Set fan operating schedule during assumed occupant standby mode time to 0 so the fan can cycle
    zone_hvac.setSupplyAirFanOperatingModeSchedule(model_set_schedule_value(zone_hvac.supplyAirFanOperatingModeSchedule.get, '12' => 0))

    return true
  end
end
