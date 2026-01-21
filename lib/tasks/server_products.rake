# frozen_string_literal: true

namespace :server_products do
  desc "Purge all server products (dev/test only)"
  task purge: :environment do
    if Rails.env.production?
      puts "ERROR: This task cannot be run in production."
      puts "If you really need to purge data in production, use the Rails console."
      exit 1
    end

    count = ServerProduct.count

    if count.zero?
      puts "No server products to purge."
      exit 0
    end

    puts "Purging #{count} server product(s)..."

    # Purge attached images first
    ServerProduct.find_each do |product|
      product.images.purge if product.images.attached?
    end

    # Delete all records (uses dependent: :nullify for nodes)
    ServerProduct.delete_all

    puts "Done! Purged #{count} server product(s)."
  end

  desc "Pre-process image variants for all server products"
  task preprocess_variants: :environment do
    count = 0
    ServerProduct.includes(images_attachments: :blob).find_each do |product|
      next unless product.images.attached?

      print "Processing #{product.name}..."
      product.preprocess_image_variants!
      puts " done"
      count += 1
    end
    puts "Processed #{count} products with images."
  end
end
