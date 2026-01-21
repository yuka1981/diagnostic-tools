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
end
