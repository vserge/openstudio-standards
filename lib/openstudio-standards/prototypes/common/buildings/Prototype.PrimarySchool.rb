# Custom changes for the PrimarySchool prototype.
# These are changes that are inconsistent with other prototype building types.
module PrimarySchool
  # hvac adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [string] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Bool] returns true if successful, false if not
  def model_custom_hvac_tweaks(model, building_type, climate_zone, prototype_input)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started building type specific HVAC adjustments')

    # add transformer
    # efficiency based on a 113 kVA transformer
    case template
    when '90.1-2004', '90.1-2007'
      transformer_efficiency = 0.969
    when '90.1-2010', '90.1-2013'
      transformer_efficiency = 0.982
    when '90.1-2016', '90.1-2019'
      transformer_efficiency = 0.987
    else
      transformer_efficiency = nil
    end
    return true unless !transformer_efficiency.nil?

    model_add_transformer(model,
                          wired_lighting_frac: 0.0119,
                          transformer_size: 112500,
                          transformer_efficiency: transformer_efficiency)

    # add extra equipment for kitchen
    add_extra_equip_kitchen(model)
    return true
  end

  # add extra equipment for kitchen
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Bool] returns true if successful, false if not
  def add_extra_equip_kitchen(model)
    kitchen_space = model.getSpaceByName('Kitchen_ZN_1_FLR_1')
    kitchen_space = kitchen_space.get
    kitchen_space_type = kitchen_space.spaceType.get
    elec_equip_def1 = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elec_equip_def2 = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elec_equip_def1.setName('Kitchen Electric Equipment Definition1')
    elec_equip_def2.setName('Kitchen Electric Equipment Definition2')
    case template
      when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019'
        elec_equip_def1.setFractionLatent(0)
        elec_equip_def1.setFractionRadiant(0.25)
        elec_equip_def1.setFractionLost(0)
        elec_equip_def2.setFractionLatent(0)
        elec_equip_def2.setFractionRadiant(0.25)
        elec_equip_def2.setFractionLost(0)
        if template == '90.1-2013' || template == '90.1-2016'
          elec_equip_def1.setDesignLevel(915)
          elec_equip_def2.setDesignLevel(570)
        elsif template == '90.1-2019'
          elec_equip_def1.setDesignLevel(555)
          elec_equip_def2.setDesignLevel(313.3)
        else
          elec_equip_def1.setDesignLevel(1032)
          elec_equip_def2.setDesignLevel(852)
        end
        # Create the electric equipment instance and hook it up to the space type
        elec_equip1 = OpenStudio::Model::ElectricEquipment.new(elec_equip_def1)
        elec_equip2 = OpenStudio::Model::ElectricEquipment.new(elec_equip_def2)
        elec_equip1.setName('Kitchen_Reach-in-Freezer')
        elec_equip2.setName('Kitchen_Reach-in-Refrigerator')
        elec_equip1.setSpaceType(kitchen_space_type)
        elec_equip2.setSpaceType(kitchen_space_type)
        elec_equip1.setSchedule(model_add_schedule(model, 'SchoolPrimary ALWAYS_ON'))
        elec_equip2.setSchedule(model_add_schedule(model, 'SchoolPrimary ALWAYS_ON'))
    end
    return true
  end

  # update water heater ambient conditions
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Bool] returns true if successful, false if not
  def update_waterheater_ambient_parameters(model)
    model.getWaterHeaterMixeds.sort.each do |water_heater|
      if water_heater.name.to_s.include?('Booster')
        water_heater.resetAmbientTemperatureSchedule
        water_heater.setAmbientTemperatureIndicator('ThermalZone')
        water_heater.setAmbientTemperatureThermalZone(model.getThermalZoneByName('Kitchen_ZN_1_FLR_1 ZN').get)
      end
    end
    return true
  end

  # swh adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [string] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Bool] returns true if successful, false if not
  def model_custom_swh_tweaks(model, building_type, climate_zone, prototype_input)
    update_waterheater_ambient_parameters(model)
    return true
  end

  # geometry adjustments specific to the prototype model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [string] the building type
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param prototype_input [Hash] hash of prototype inputs
  # @return [Bool] returns true if successful, false if not
  def model_custom_geometry_tweaks(model, building_type, climate_zone, prototype_input)
    # Set original building North axis
    model_set_building_north_axis(model, 0.0)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.PrimarySchool', 'Adding skylights.')
    model_add_skylights(model, 'geometry/ASHRAEPrimarySchoolSkylights.osm')

    return true
  end

  # @!group AirTerminalSingleDuctVAVReheat
  # Set the initial minimum damper position based on OA rate of the space and the template.
  # Zones with low OA per area get lower initial guesses.
  # Final position will be adjusted upward as necessary by Standards.AirLoopHVAC.apply_minimum_vav_damper_positions
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @param zone_oa_per_area [Double] the zone outdoor air per area in m^3/s*m^2
  # @return [Bool] returns true if successful, false if not
  def air_terminal_single_duct_vav_reheat_apply_initial_prototype_damper_position(air_terminal_single_duct_vav_reheat, zone_oa_per_area)
    min_damper_position = template == '90.1-2010' || template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019' ? 0.2 : 0.3

    # Set the minimum flow fraction
    air_terminal_single_duct_vav_reheat.setConstantMinimumAirFlowFraction(min_damper_position)

    return true
  end

  # Type of SAT reset for this building type
  #
  # @param air_loop_hvac [OpenStudio::model::AirLoopHVAC] air loop
  # @return [String] Returns type of SAT reset
  def air_loop_hvac_supply_air_temperature_reset_type(air_loop_hvac)
    return 'oa'
  end

  # List transfer air target and source zones, and air flow (cfm)
  # code_sections [90.1-2019_6.5.7.1], [90.1-2016_6.5.7.1]
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] target zones (key) and source zones (value) and air flow (value)
  def model_transfer_air_target_and_source_zones(model)
    model_transfer_air_target_and_source_zones_hash = {
      'Bath_ZN_1_FLR_1 ZN' => ['Library_Media_Center_ZN_1_FLR_1 ZN', 600.0]
    }
    return model_transfer_air_target_and_source_zones_hash
  end
end
