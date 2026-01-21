# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "db:seed:export_server_products", type: :task do
  let(:images_dir) { Rails.root.join("db/seeds/images/server_products") }
  let(:json_path) { Rails.root.join("db/seeds/server_products.json") }
  let(:task) { Rake::Task["db:seed:export_server_products"] }

  before do
    # Load rake tasks
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:seed:export_server_products")
    # Re-enable task so it can be run multiple times in tests
    task.reenable
  end

  after do
    # Clean up generated files
    FileUtils.rm_rf(images_dir)
    FileUtils.rm_f(json_path)
  end

  # Helper to run task and suppress stdout
  def run_task
    silence_stream($stdout) { task.invoke }
  end

  # Suppress output during tests
  def silence_stream(stream)
    old_stream = stream.dup
    stream.reopen(File::NULL)
    stream.sync = true
    yield
  ensure
    stream.reopen(old_stream)
    old_stream.close
  end

  describe "directory creation" do
    it "creates the images directory" do
      create(:server_product)

      expect { run_task }.not_to raise_error
      expect(images_dir).to exist
    end
  end

  describe "JSON export" do
    it "exports product attributes to JSON" do
      product = create(:server_product,
        name: "QuantaGrid D54Q-2U",
        product_series: "QuantaGrid",
        form_factor: "2U",
        rack_height: 2,
        qct_product_url: "https://www.qct.io/product/test",
        socket_count: 2,
        max_tdp_watts: 350,
        max_memory_gb: 8192,
        dimm_slots: 32,
        memory_types: [ "DDR5" ],
        max_memory_speed_mhz: 5600,
        drive_bays: [ { "count" => 24, "type" => "NVMe" } ],
        pcie_slots: [ { "count" => 4, "generation" => "5.0" } ],
        power_supply_options: [ "1600W" ],
        gpu_support: true,
        network_options: [ "100GbE" ],
        cpu_generations: [ "5th Gen Xeon" ])

      run_task

      expect(json_path).to exist
      json_data = JSON.parse(File.read(json_path))

      expect(json_data).to have_key("products")
      expect(json_data["products"].size).to eq(1)

      exported = json_data["products"].first
      expect(exported["name"]).to eq("QuantaGrid D54Q-2U")
      expect(exported["product_series"]).to eq("QuantaGrid")
      expect(exported["form_factor"]).to eq("2U")
      expect(exported["rack_height"]).to eq(2)
      expect(exported["socket_count"]).to eq(2)
      expect(exported["max_tdp_watts"]).to eq(350)
      expect(exported["max_memory_gb"]).to eq(8192)
      expect(exported["dimm_slots"]).to eq(32)
      expect(exported["memory_types"]).to eq([ "DDR5" ])
      expect(exported["max_memory_speed_mhz"]).to eq(5600)
      expect(exported["drive_bays"]).to eq([ { "count" => 24, "type" => "NVMe" } ])
      expect(exported["pcie_slots"]).to eq([ { "count" => 4, "generation" => "5.0" } ])
      expect(exported["gpu_support"]).to eq(true)
      expect(exported["cpu_generations"]).to eq([ "5th Gen Xeon" ])
    end

    it "excludes nil attributes from exported JSON" do
      create(:server_product,
        name: "Minimal Product",
        power_supply_options: nil,
        network_options: nil)

      run_task

      json_data = JSON.parse(File.read(json_path))
      exported = json_data["products"].first

      expect(exported).not_to have_key("power_supply_options")
      expect(exported).not_to have_key("network_options")
    end
  end

  describe "image export" do
    it "exports attached images with slugified filenames" do
      product = create(:server_product, name: "QuantaGrid D54Q-2U")

      # Attach a test image
      product.images.attach(
        io: StringIO.new("fake image content"),
        filename: "original_image.png",
        content_type: "image/png"
      )

      run_task

      # Check image was exported with slugified name
      expected_image_path = images_dir.join("quantagrid-d54q-2u.png")
      expect(expected_image_path).to exist
      expect(File.read(expected_image_path)).to eq("fake image content")

      # Check JSON has the image filename
      json_data = JSON.parse(File.read(json_path))
      exported = json_data["products"].first
      expect(exported["image_filename"]).to eq("quantagrid-d54q-2u.png")
    end

    it "preserves original file extension" do
      product = create(:server_product, name: "Test Server")
      product.images.attach(
        io: StringIO.new("jpeg content"),
        filename: "photo.jpg",
        content_type: "image/jpeg"
      )

      run_task

      expected_image_path = images_dir.join("test-server.jpg")
      expect(expected_image_path).to exist
    end
  end

  describe "products without images" do
    it "sets image_filename to nil for products without images" do
      create(:server_product, name: "No Image Product")

      run_task

      json_data = JSON.parse(File.read(json_path))
      exported = json_data["products"].first

      expect(exported["image_filename"]).to be_nil
    end
  end

  describe "multiple products" do
    it "exports all products" do
      create(:server_product, name: "Product A")
      create(:server_product, name: "Product B")
      create(:server_product, name: "Product C")

      run_task

      json_data = JSON.parse(File.read(json_path))
      expect(json_data["products"].size).to eq(3)
    end
  end
end
