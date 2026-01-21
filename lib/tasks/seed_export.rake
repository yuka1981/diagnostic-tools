# frozen_string_literal: true

namespace :db do
  namespace :seed do
    desc "Export server products to seed files"
    task export_server_products: :environment do
      images_dir = Rails.root.join("db/seeds/images/server_products")
      FileUtils.mkdir_p(images_dir)

      products = ServerProduct.order(:name).map do |product|
        # Generate slug for image filename
        slug = product.name.parameterize
        image_filename = nil

        # Export first attached image
        if product.images.attached?
          image = product.images.first
          ext = File.extname(image.filename.to_s).presence || ".png"
          image_filename = "#{slug}#{ext}"

          File.open(images_dir.join(image_filename), "wb") do |f|
            f.write(image.download)
          end
        end

        product.attributes
          .slice(*%w[name product_series form_factor rack_height qct_product_url
                     socket_count max_tdp_watts max_memory_gb dimm_slots memory_types
                     max_memory_speed_mhz drive_bays pcie_slots power_supply_options
                     gpu_support network_options cpu_generations])
          .compact
          .merge("image_filename" => image_filename)
          .compact
      end

      json_path = Rails.root.join("db/seeds/server_products.json")
      File.write(json_path, JSON.pretty_generate({ "products" => products }))

      puts "Exported #{products.size} products to #{json_path}"
      puts "Images saved to #{images_dir}"
    end
  end
end
