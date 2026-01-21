# Server Product Seed Data Export

## Overview

Export current server product data (46 records with images) to seed files so developers can populate their local database without scraping the QCT website.

## File Structure

```
db/
├── seeds.rb                          # Main entry point, loads server_products
├── seeds/
│   ├── server_products.json          # Product data (46 records)
│   └── images/
│       └── server_products/
│           ├── quantagrid-d75h-10u.png
│           ├── quantagrid-d54x.png
│           └── ...                   # ~46 image files
```

- Images named by slugified product name (e.g., `QuantaGrid D54X` → `quantagrid-d54x.png`)
- JSON file contains all product attributes except binary image data
- Each product record includes an `image_filename` field referencing the local image

## JSON Data Structure

Each product in `server_products.json`:

```json
{
  "products": [
    {
      "name": "QuantaGrid D75H-10U",
      "product_series": "QuantaGrid",
      "form_factor": "10U",
      "rack_height": 10,
      "qct_product_url": "https://www.qct.io/product/index/Server/...",
      "socket_count": 2,
      "max_memory_gb": 8192,
      "dimm_slots": 32,
      "memory_types": ["DDR5"],
      "drive_bays": [{"type": "SSD", "count": 8, "form_factor": "2.5"}],
      "pcie_slots": [{"count": 2, "lanes": 16, "generation": "5"}],
      "gpu_support": false,
      "cpu_generations": [],
      "image_filename": "quantagrid-d75h-10u.png"
    }
  ]
}
```

- `image_filename` maps to file in `db/seeds/images/server_products/`
- Nullable fields omitted when empty
- Arrays stored as-is (Rails handles JSONB conversion)

## Seeding Logic

Update `db/seeds.rb`:

```ruby
# Load server products
server_products_path = Rails.root.join("db/seeds/server_products.json")
if server_products_path.exist?
  data = JSON.parse(server_products_path.read)
  images_dir = Rails.root.join("db/seeds/images/server_products")

  data["products"].each do |attrs|
    image_filename = attrs.delete("image_filename")

    product = ServerProduct.find_or_initialize_by(name: attrs["name"])
    product.assign_attributes(attrs)
    product.save!

    # Attach image if file exists and not already attached
    if image_filename
      image_path = images_dir.join(image_filename)
      if image_path.exist? && product.images.none?
        product.images.attach(
          io: File.open(image_path),
          filename: image_filename,
          content_type: Marcel::MimeType.for(image_path)
        )
      end
    end
  end

  puts "Seeded #{data['products'].size} server products"
end
```

**Behavior:**
- Finds existing product by `name`, updates attributes if found
- Only attaches image if product has no images (avoids duplicates)
- Silent skip if JSON file missing (allows partial seeding)

## Export Rake Task

Create `lib/tasks/seed_export.rake`:

```ruby
namespace :db do
  namespace :seed do
    desc "Export server products to seed files"
    task export_server_products: :environment do
      images_dir = Rails.root.join("db/seeds/images/server_products")
      FileUtils.mkdir_p(images_dir)

      products = ServerProduct.all.map do |product|
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
```

**Usage:** `bin/rails db:seed:export_server_products`

## Workflow

1. Run `bin/rails db:seed:export_server_products` to generate seed files
2. Commit generated files to repo
3. Any developer can run `bin/rails db:seed` to populate their local database

## Implementation Tasks

1. Create `lib/tasks/seed_export.rake` with export task
2. Update `db/seeds.rb` with loading logic
3. Run export task to generate `db/seeds/server_products.json` and images
4. Verify seeding works on fresh database
5. Commit all seed files to repository
