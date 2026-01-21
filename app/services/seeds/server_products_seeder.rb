# frozen_string_literal: true

module Seeds
  class ServerProductsSeeder
    Result = Struct.new(:success, :seeded_count, keyword_init: true) do
      def success?
        success
      end
    end

    attr_reader :json_path, :images_dir

    def initialize(json_path: nil, images_dir: nil)
      @json_path = json_path || Rails.root.join("db/seeds/server_products.json")
      @images_dir = images_dir || Rails.root.join("db/seeds/images/server_products")
    end

    def call
      return Result.new(success: true, seeded_count: 0) unless json_path.exist?

      data = JSON.parse(json_path.read)
      seeded_count = 0

      ServerProduct.transaction do
        data["products"].each do |attrs|
          attrs = attrs.dup
          image_filename = attrs.delete("image_filename")

          product = ServerProduct.find_or_initialize_by(name: attrs["name"])
          product.assign_attributes(attrs)
          product.save!

          attach_image(product, image_filename) if image_filename.present?

          seeded_count += 1
        end
      end

      Result.new(success: true, seeded_count: seeded_count)
    end

    private

    def attach_image(product, image_filename)
      return if product.images.any?

      image_path = images_dir.join(image_filename)
      return unless image_path.exist?

      # Read file into memory to avoid closed stream issues within transaction
      content = File.binread(image_path)
      product.images.attach(
        io: StringIO.new(content),
        filename: image_filename,
        content_type: Marcel::MimeType.for(image_path)
      )
    end
  end
end
