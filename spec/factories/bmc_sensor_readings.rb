FactoryBot.define do
  factory :bmc_sensor_reading do
    node
    sensor_type { "temperature" }
    sensor_name { "cpu1" }
    value { 52.0 }
    unit { "celsius" }
    status { "ok" }
    recorded_at { Time.current }
  end
end
