# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seeds::ServerProductsSeeder do
  describe "#call" do
    subject(:seeder) { described_class.new(json_path: json_path, images_dir: images_dir) }

    let(:json_path) { Rails.root.join("tmp/test_seeds/server_products.json") }
    let(:images_dir) { Rails.root.join("tmp/test_seeds/images/server_products") }

    before do
      FileUtils.mkdir_p(images_dir)
    end

    after do
      FileUtils.rm_rf(Rails.root.join("tmp/test_seeds"))
    end

    context "when JSON file is missing" do
      before do
        FileUtils.rm_f(json_path)
      end

      it "returns success with zero products seeded" do
        result = seeder.call
        expect(result).to be_success
        expect(result.seeded_count).to eq(0)
      end

      it "does not create any products" do
        expect { seeder.call }.not_to change(ServerProduct, :count)
      end
    end

    context "with valid JSON data" do
      let(:json_data) do
        {
          products: [
            {
              name: "QuantaGrid D54Q-2U",
              product_series: "QuantaGrid",
              form_factor: "2U",
              rack_height: 2,
              socket_count: 2,
              max_tdp_watts: 350,
              gpu_support: true
            },
            {
              name: "QuantaPlex T42S-2U",
              product_series: "QuantaPlex",
              form_factor: "2U",
              rack_height: 2,
              socket_count: 4,
              max_tdp_watts: 250,
              gpu_support: false
            }
          ]
        }
      end

      before do
        File.write(json_path, json_data.to_json)
      end

      it "creates new products from JSON data" do
        expect { seeder.call }.to change(ServerProduct, :count).by(2)
      end

      it "returns success result with seeded count" do
        result = seeder.call
        expect(result).to be_success
        expect(result.seeded_count).to eq(2)
      end

      it "sets correct attributes on created products" do
        seeder.call
        product = ServerProduct.find_by(name: "QuantaGrid D54Q-2U")
        expect(product.product_series).to eq("QuantaGrid")
        expect(product.form_factor).to eq("2U")
        expect(product.rack_height).to eq(2)
        expect(product.socket_count).to eq(2)
        expect(product.max_tdp_watts).to eq(350)
        expect(product.gpu_support).to be true
      end
    end

    context "when product already exists (idempotent update)" do
      let!(:existing_product) do
        create(:server_product,
               name: "QuantaGrid D54Q-2U",
               product_series: "OldSeries",
               max_tdp_watts: 200,
               gpu_support: false)
      end

      let(:json_data) do
        {
          products: [
            {
              name: "QuantaGrid D54Q-2U",
              product_series: "QuantaGrid",
              form_factor: "2U",
              max_tdp_watts: 350,
              gpu_support: true
            }
          ]
        }
      end

      before do
        File.write(json_path, json_data.to_json)
      end

      it "does not create a duplicate product" do
        expect { seeder.call }.not_to change(ServerProduct, :count)
      end

      it "updates attributes of existing product" do
        seeder.call
        existing_product.reload
        expect(existing_product.product_series).to eq("QuantaGrid")
        expect(existing_product.max_tdp_watts).to eq(350)
        expect(existing_product.gpu_support).to be true
      end

      it "returns success with correct count" do
        result = seeder.call
        expect(result).to be_success
        expect(result.seeded_count).to eq(1)
      end
    end

    context "with image attachment" do
      let(:json_data) do
        {
          products: [
            {
              name: "QuantaGrid D54Q-2U",
              product_series: "QuantaGrid",
              image_filename: "quantagrid_d54q.png"
            }
          ]
        }
      end

      let(:test_image_path) { images_dir.join("quantagrid_d54q.png") }

      before do
        File.write(json_path, json_data.to_json)
        # Create a minimal valid PNG file (1x1 transparent pixel)
        png_data = [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, # IDAT chunk
          0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
          0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, # IEND chunk
          0x42, 0x60, 0x82
        ].pack("C*")
        File.binwrite(test_image_path, png_data)
      end

      it "attaches image to the product" do
        seeder.call
        product = ServerProduct.find_by(name: "QuantaGrid D54Q-2U")
        expect(product.images).to be_attached
        expect(product.images.first.filename.to_s).to eq("quantagrid_d54q.png")
      end

      it "detects content type using Marcel" do
        seeder.call
        product = ServerProduct.find_by(name: "QuantaGrid D54Q-2U")
        expect(product.images.first.content_type).to eq("image/png")
      end
    end

    context "when product already has images" do
      let!(:existing_product) do
        product = create(:server_product, name: "QuantaGrid D54Q-2U")
        # Attach an existing image
        product.images.attach(
          io: StringIO.new("fake image data"),
          filename: "existing_image.png",
          content_type: "image/png"
        )
        product
      end

      let(:json_data) do
        {
          products: [
            {
              name: "QuantaGrid D54Q-2U",
              product_series: "QuantaGrid",
              image_filename: "new_image.png"
            }
          ]
        }
      end

      let(:test_image_path) { images_dir.join("new_image.png") }

      before do
        File.write(json_path, json_data.to_json)
        # Create a minimal PNG file
        png_data = [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
          0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
          0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82
        ].pack("C*")
        File.binwrite(test_image_path, png_data)
      end

      it "does not attach additional images" do
        expect { seeder.call }.not_to change { existing_product.reload.images.count }
      end

      it "keeps the original image" do
        seeder.call
        existing_product.reload
        expect(existing_product.images.first.filename.to_s).to eq("existing_image.png")
      end
    end

    context "when image file is missing" do
      let(:json_data) do
        {
          products: [
            {
              name: "QuantaGrid D54Q-2U",
              product_series: "QuantaGrid",
              image_filename: "nonexistent.png"
            }
          ]
        }
      end

      before do
        File.write(json_path, json_data.to_json)
      end

      it "creates product without image" do
        seeder.call
        product = ServerProduct.find_by(name: "QuantaGrid D54Q-2U")
        expect(product).to be_present
        expect(product.images).not_to be_attached
      end

      it "returns success" do
        result = seeder.call
        expect(result).to be_success
      end
    end

    context "when image_filename is nil" do
      let(:json_data) do
        {
          products: [
            {
              name: "QuantaGrid D54Q-2U",
              product_series: "QuantaGrid",
              image_filename: nil
            }
          ]
        }
      end

      before do
        File.write(json_path, json_data.to_json)
      end

      it "creates product without attempting image attachment" do
        seeder.call
        product = ServerProduct.find_by(name: "QuantaGrid D54Q-2U")
        expect(product).to be_present
        expect(product.images).not_to be_attached
      end
    end

    context "with default paths" do
      subject(:seeder) { described_class.new }

      it "uses Rails.root paths by default" do
        expect(seeder.json_path).to eq(Rails.root.join("db/seeds/server_products.json"))
        expect(seeder.images_dir).to eq(Rails.root.join("db/seeds/images/server_products"))
      end
    end
  end
end
