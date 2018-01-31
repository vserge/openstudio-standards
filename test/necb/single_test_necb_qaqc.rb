require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'
require 'json'
require 'parallel'
require 'etc'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

def run_dir(test_name)
  # always generate test output in specially named 'output' directory so result files are not made part of the measure
  "#{File.dirname(__FILE__)}/output#{Time.now.strftime("%m-%d")}/#{test_name}"
end

def model_out_path(test_name)
  "#{run_dir(test_name)}/ExampleModel.osm"
end

def workspace_path(test_name)
  "#{run_dir(test_name)}/ModelToIdf/in.idf"
end

def sql_path(test_name)
  "#{run_dir(test_name)}/run/eplusout.sql"
end

def report_path(test_name)
  "#{run_dir(test_name)}/report.html"
end

#LargeOffice
class SingleTestNECBQAQC < CreateDOEPrototypeBuildingTest

  building_types = [

#    "FullServiceRestaurant",
#    "LargeHotel",
#    "LargeOffice",
#    "MediumOffice",
#    "MidriseApartment",
      "Outpatient",
#    "PrimarySchool",
#    "QuickServiceRestaurant",
#    "RetailStandalone",
#    "RetailStripmall",
#    "SmallHotel",
#    "SmallOffice",
#    "Warehouse"

  ]

  templates = 'NECB2011'
  climate_zones = 'NECB HDD Method'

  epw_files = [
      'CAN_AB_Calgary.Intl.AP.718770_CWEC2016.epw'
  ]

  start = Time.now
  run_argument_array = []
  building_types.each do |building|
    epw_files.each do |epw|
      run_argument_array << {'building' => building, 'epw' => epw}
    end
  end

  processess = (Parallel::processor_count - 1)
  puts "processess #{processess}"
  Parallel.map(run_argument_array, in_processes: processess) {|info|
    test_name = "#{info['building']}_#{info['epw']}"
    puts info
    puts "creating #{test_name}"

    if File.exist?("#{run_dir(test_name)}/final.osm")

      model = BTAP::FileIO::load_osm("#{run_dir(test_name)}/final.osm")
      sql = OpenStudio::SqlFile.new(OpenStudio::Path.new(sql_path(test_name)))
      model.setSqlFile(sql)
      qaqc = BTAP.perform_qaqc(model)
      File.open("#{run_dir(test_name)}/qaqc.json", 'w') {|f| f.write(JSON.pretty_generate(qaqc))}
      puts JSON.pretty_generate(qaqc)
    else
      unless File.exist?(run_dir(test_name))
        FileUtils.mkdir_p(run_dir(test_name))
      end
      #assert(File.exist?(run_dir(test_name)))

      if File.exist?(report_path(test_name))
        FileUtils.rm(report_path(test_name))
      end

      #assert(File.exist?(model_in_path))

      if File.exist?(model_out_path(test_name))
        FileUtils.rm(model_out_path(test_name))
      end
      output_folder = "#{File.dirname(__FILE__)}/output#{Time.now.strftime("%m-%d")}/#{test_name}"
      model = OpenStudio::Model::Model.new
      model.create_prototype_building(info['building'], templates, climate_zones, info['epw'], output_folder)
      BTAP::Environment::WeatherFile.new(info['epw']).set_weather_file(model)
      model_run_simulation_and_log_errors(model, run_dir(test_name))
      qaqc = BTAP.perform_qaqc(model)
      File.open("#{output_folder}/qaqc.json", 'w') {|f| f.write(JSON.pretty_generate(qaqc))}
      puts JSON.pretty_generate(qaqc)
    end


  }
  BTAP::FileIO.compile_qaqc_results("#{File.dirname(__FILE__)}/output#{Time.now.strftime("%m-%d")}")
  puts "completed in #{Time.now - start} secs"
end
