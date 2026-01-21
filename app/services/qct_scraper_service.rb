# frozen_string_literal: true

require "net/http"
require "nokogiri"

class QctScraperService
  BASE_URL = "https://www.qct.io/product/index/Server/rackmount-server"

  # Use a realistic browser User-Agent to avoid blocking
  USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  # URL path segments: /product/index/Server/rackmount-server/{category}/{product}
  # Base URL: /product/index/Server/rackmount-server = 4 segments
  # Category: /product/index/Server/rackmount-server/1U-Rackmount-Server = 5 segments
  # Product: /product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X = 6 segments
  CATEGORY_PATH_SEGMENTS = 5
  PRODUCT_PATH_SEGMENTS = 6

  # Rate limiting: delay between requests (in seconds)
  DEFAULT_REQUEST_DELAY = 1.0

  # Maximum pages to fetch per category (safety limit)
  MAX_PAGES_PER_CATEGORY = 20

  Result = Struct.new(:added_count, :updated_count, :errors, :new_products, keyword_init: true)

  def initialize(request_delay: DEFAULT_REQUEST_DELAY)
    @request_delay = request_delay
  end

  def sync_all
    product_urls = fetch_product_listing
    added = []
    updated = []
    errors = []

    product_urls.each do |url|
      result = sync_product(url)
      case result
      when :added then added << url
      when :updated then updated << url
      else errors << { url: url, error: result }
      end
    rescue StandardError => e
      errors << { url: url, error: e.message }
    end

    Result.new(
      added_count: added.size,
      updated_count: updated.size,
      errors: errors,
      new_products: added
    )
  rescue StandardError => e
    Result.new(
      added_count: 0,
      updated_count: 0,
      errors: [ { url: BASE_URL, error: e.message } ],
      new_products: []
    )
  end

  def sync_product(url)
    rate_limit
    html = fetch_page(url)
    attrs = parse_product_page(html, url)

    # Extract image_url before assigning attributes (we'll handle it separately)
    image_url = attrs.delete(:image_url)

    product = ServerProduct.find_or_initialize_by(qct_product_url: url)
    is_new = product.new_record?

    product.assign_attributes(attrs)
    product.last_synced_at = Time.current
    product.save!

    # Download and attach the image if URL is present and image not already attached
    download_and_attach_image(product, image_url) if image_url.present?

    is_new ? :added : :updated
  rescue StandardError => e
    e.message
  end

  private

  def rate_limit
    sleep(@request_delay) if @request_delay.positive?
  end

  def fetch_page(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = USER_AGENT

    response = http.request(request)
    raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def download_and_attach_image(product, image_url)
    # Skip if product already has an image with the same source URL
    return if product.images.any? { |img| img.blob&.metadata&.dig("source_url") == image_url }

    rate_limit
    image_data = fetch_image(image_url)
    return unless image_data

    filename = File.basename(URI.parse(image_url).path)
    content_type = determine_content_type(filename)

    product.images.attach(
      io: StringIO.new(image_data),
      filename: filename,
      content_type: content_type,
      metadata: { source_url: image_url }
    )
  rescue StandardError => e
    # Log error but don't fail the sync
    Rails.logger.warn("Failed to download image for #{product.name}: #{e.message}")
  end

  def fetch_image(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = USER_AGENT

    response = http.request(request)
    return nil unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def determine_content_type(filename)
    extension = File.extname(filename).downcase
    case extension
    when ".png" then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".gif" then "image/gif"
    when ".webp" then "image/webp"
    else "application/octet-stream"
    end
  end

  def fetch_product_listing
    rate_limit
    html = fetch_page(BASE_URL)
    doc = Nokogiri::HTML(html)

    # Collect all rackmount-server URLs from main page (including paginated pages)
    all_urls = fetch_all_pages_urls(BASE_URL, doc)

    # Separate category URLs from product URLs (explicitly filter both)
    category_urls = all_urls.select { |url| category_url?(url) }
    product_urls = all_urls.select { |url| product_url?(url) }

    # Stage 2: Visit each category page to collect product URLs (with pagination)
    category_urls.each do |category_url|
      category_product_urls = fetch_products_from_category(category_url)
      product_urls.concat(category_product_urls)
    rescue StandardError
      # Continue processing other categories if one fails
      next
    end

    product_urls.uniq
  end

  def fetch_products_from_category(category_url)
    rate_limit
    html = fetch_page(category_url)
    doc = Nokogiri::HTML(html)

    # Fetch products from all pages of this category (explicitly filter for product URLs)
    fetch_all_pages_urls(category_url, doc).select { |url| product_url?(url) }
  end

  def fetch_all_pages_urls(base_url, first_page_doc)
    all_urls = extract_rackmount_urls(first_page_doc)
    current_page = 1

    # Check for pagination and fetch additional pages
    while current_page < MAX_PAGES_PER_CATEGORY
      next_page_url = find_next_page_url(base_url, first_page_doc, current_page)
      break unless next_page_url

      rate_limit
      begin
        html = fetch_page(next_page_url)
        doc = Nokogiri::HTML(html)
        page_urls = extract_rackmount_urls(doc)

        # Stop if no new URLs found (we've reached the end)
        break if page_urls.empty? || (page_urls - all_urls).empty?

        all_urls.concat(page_urls)
        current_page += 1
        first_page_doc = doc
      rescue StandardError
        # Stop pagination on error, return what we have
        break
      end
    end

    all_urls.uniq
  end

  def find_next_page_url(base_url, doc, current_page)
    next_page = current_page + 1

    # Look for explicit next page link
    next_link = doc.at_css("a[href*='page=#{next_page}']")
    return nil unless next_link

    href = next_link["href"]
    return nil if href.nil? || href.empty?

    # Build absolute URL
    if href.start_with?("http")
      href
    elsif href.start_with?("?")
      # Query string only, append to base URL
      uri = URI.parse(base_url)
      uri.query = href.sub(/^\?/, "")
      uri.to_s
    else
      "https://www.qct.io#{href}"
    end
  end

  def extract_rackmount_urls(doc)
    doc.css('a[href*="/product/index/Server/rackmount-server/"]').filter_map do |link|
      href = link["href"]
      next if href == "/product/index/Server/rackmount-server" || href == BASE_URL

      href.start_with?("http") ? href : "https://www.qct.io#{href}"
    end.uniq
  end

  def category_url?(url)
    # Count path segments to determine if URL is a category
    # /product/index/Server/rackmount-server/1U-Rackmount-Server = 5 segments (category)
    path = URI.parse(url).path
    segments = path.split("/").reject(&:empty?)
    segments.size == CATEGORY_PATH_SEGMENTS
  end

  def product_url?(url)
    # Count path segments to determine if URL is a product
    # /product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X = 6 segments (product)
    path = URI.parse(url).path
    segments = path.split("/").reject(&:empty?)
    segments.size == PRODUCT_PATH_SEGMENTS
  end

  def parse_product_page(html, url)
    doc = Nokogiri::HTML(html)

    # Extract specifications section for targeted parsing
    specs_text = extract_specifications_text(doc)
    full_text = doc.text

    model_name = extract_model_name(doc)
    product_series = extract_series(model_name)
    form_factor = extract_form_factor(doc, model_name, specs_text)
    rack_height = form_factor&.match(/(\d+)U/i)&.captures&.first&.to_i || 1

    {
      name: model_name,
      product_series: product_series,
      form_factor: form_factor,
      rack_height: rack_height,
      qct_product_url: url,
      image_url: extract_image_url(doc),
      cpu_generations: extract_cpu_generations(specs_text, full_text),
      socket_count: extract_socket_count(specs_text, full_text),
      max_memory_gb: extract_max_memory(specs_text, full_text),
      dimm_slots: extract_dimm_slots(specs_text, full_text),
      memory_types: extract_memory_types(specs_text, full_text),
      drive_bays: extract_drive_bays(specs_text, full_text),
      pcie_slots: extract_pcie_slots(specs_text, full_text),
      gpu_support: extract_gpu_support(specs_text, full_text)
    }.compact
  end

  def extract_specifications_text(doc)
    # Strategy 1: Look for section/div with specifications ID or class
    specs_section = doc.at_css("section#specifications, div#specifications, #specifications") ||
                    doc.at_css("[id*='spec']:not(a)") ||
                    doc.at_css(".specifications, [class*='spec']")
    return specs_section.text if specs_section&.text.present?

    # Strategy 2: Find tables containing specification keywords (Processor, Memory, Storage)
    # QCT pages typically have specs in table format
    spec_keywords = /Processor|Memory|Storage|Form Factor|Expansion Slot/i
    doc.css("table").each do |table|
      table_text = table.text
      # Look for tables that contain multiple spec-related keywords
      keyword_matches = table_text.scan(spec_keywords).size
      return table_text if keyword_matches >= 2
    end

    # Strategy 3: Find definition lists with spec data
    doc.css("dl").each do |dl|
      dl_text = dl.text
      keyword_matches = dl_text.scan(spec_keywords).size
      return dl_text if keyword_matches >= 2
    end

    # Strategy 4: Look for a section after "Specifications" heading
    specs_heading = doc.at_xpath("//h2[contains(text(), 'Specifications')] | //h3[contains(text(), 'Specifications')]")
    if specs_heading
      # Get the next sibling elements until next heading
      content = []
      sibling = specs_heading.next_element
      while sibling && !sibling.name.match?(/^h[1-3]$/i)
        content << sibling.text
        sibling = sibling.next_element
      end
      return content.join(" ") if content.any?
    end

    # Fallback: return empty string (let full_text fallback handle it)
    ""
  end

  def extract_model_name(doc)
    # Try various selectors for product name
    name_element = doc.at_css("h1, .product-name, .product-title")
    name_element&.text&.strip
  end

  def extract_image_url(doc)
    # QCT uses different image paths:
    # - Product gallery: /upload/website/product/gallery/normal/ (high quality)
    # - Product gallery: /upload/website/product/gallery/thumbnail/
    # - Cover images: /upload/website/product/images/ (listing thumbnails)
    # - Logos/icons: /upload/website/product/icon/ (should skip)

    # Priority 1: Gallery images (product detail page - best quality)
    img = doc.at_css("img[src*='/gallery/normal/']") ||
          doc.at_css("img[src*='/gallery/thumbnail/']")

    # Priority 2: Cover images from listing (product images folder)
    img ||= doc.at_css("img[src*='/product/images/']")

    # Priority 3: Generic image_block (listing page structure)
    img ||= doc.at_css(".image_block img")

    return nil unless img

    src = img["src"]
    return nil if src.blank?

    # Skip logos and icons
    return nil if src.include?("/icon/") || src.include?("/media/")

    # Convert relative URLs to absolute
    if src.start_with?("http")
      src
    else
      "https://www.qct.io#{src}"
    end
  end

  def extract_series(model_name)
    return nil unless model_name

    %w[QuantaGrid QuantaPlex QuantaMesh QuantaEdge].find { |s| model_name.include?(s) }
  end

  def extract_form_factor(doc, model_name, specs_text)
    # First try to extract from model name (e.g., "D54Q-2U")
    ff_match = model_name&.match(/(\d+U)/i)
    return ff_match[1].upcase if ff_match

    # Try specs section first, then full page
    text = specs_text.presence || doc.text
    text[/Form Factor[:\s]*(\d+U)/i, 1]&.upcase
  end

  def extract_cpu_generations(specs_text, full_text)
    text = specs_text.presence || full_text

    generations = []
    # Handle combined formats like "5th/4th Gen Intel Xeon" as well as "5th Gen Xeon"
    generations << "5th Gen Xeon" if text =~ /5th[\/\w\s]*Gen.*Xeon|Emerald\s*Rapids/i
    generations << "4th Gen Xeon" if text =~ /4th[\/\w\s]*Gen.*Xeon|Sapphire\s*Rapids/i
    generations << "3rd Gen Xeon" if text =~ /3rd[\/\w\s]*Gen.*Xeon|Ice\s*Lake/i
    # Also match "Intel Xeon Scalable" without generation (older models)
    generations << "Xeon Scalable" if generations.empty? && text =~ /Xeon.*Scalable/i
    generations
  end

  def extract_socket_count(specs_text, full_text)
    text = specs_text.presence || full_text

    # QCT format: "Number of Processors: 2 Processors" or "2 Processors"
    match = text[/Number of Processors[:\s]*(\d+)/i, 1] ||
            text[/(\d+)\s*Processors?\b/i, 1] ||
            text[/(\d+)\s*Socket/i, 1]
    match&.to_i
  end

  def extract_max_memory(specs_text, full_text)
    text = specs_text.presence || full_text

    # QCT format: "Up to 3TB" or "Up to 8192 GB" or "8192 GB max"
    mem_match = text[/Up to (\d+)\s*(TB|GB)/i] ||
                text[/(\d+)\s*(TB|GB)\s*(?:max|maximum)/i]
    return nil unless mem_match

    value = mem_match[/(\d+)/, 1].to_i
    unit = mem_match[/(TB|GB)/i, 1]
    unit&.upcase == "TB" ? value * 1024 : value
  end

  def extract_dimm_slots(specs_text, full_text)
    text = specs_text.presence || full_text

    # QCT format: "Total Slots: 24" or "24 DIMM slots"
    match = text[/Total Slots[:\s]*(\d+)/i, 1] ||
            text[/(\d+)\s*DIMM/i, 1] ||
            text[/Memory Slots[:\s]*(\d+)/i, 1]
    match&.to_i
  end

  def extract_memory_types(specs_text, full_text)
    text = specs_text.presence || full_text

    types = []
    types << "DDR5" if text =~ /DDR5/i
    types << "DDR4" if text =~ /DDR4/i
    types << "DDR3" if text =~ /DDR3/i
    types
  end

  def extract_drive_bays(specs_text, full_text)
    text = specs_text.presence || full_text
    bays = []

    # QCT format: "(12) 3.5"/2.5" hot-plug SATA/SAS" or "(24) 2.5" hot-plug NVMe SSD"
    # Pattern: (count) size hot-plug type
    text.scan(/\((\d+)\)[^(]*?(NVMe|SAS|SATA|SSD|HDD)/i).each do |count, type|
      # Normalize type
      normalized_type = case type.upcase
      when "NVME" then "NVME"
      when "SSD" then "SSD"
      when "HDD" then "HDD"
      else type.upcase
      end

      bays << {
        "count" => count.to_i,
        "type" => normalized_type,
        "form_factor" => "2.5"
      }
    end

    # Fallback to old pattern if QCT format doesn't match
    if bays.empty?
      text.scan(/(\d+)\s*x?\s*(NVMe|SAS|SATA|SSD|HDD)\s*([\d.]+)?/i).each do |count, type, form_factor|
        bays << {
          "count" => count.to_i,
          "type" => type.upcase,
          "form_factor" => form_factor || "2.5"
        }
      end
    end

    bays.uniq { |b| [ b["count"], b["type"] ] }
  end

  def extract_pcie_slots(specs_text, full_text)
    text = specs_text.presence || full_text
    slots = []

    # QCT format: "(1) PCIe Gen3 x16" or "(2) PCIe Gen3 x8"
    text.scan(/\((\d+)\)[^(]*?PCIe[^(]*?(?:Gen\s*)?(\d+)[^(]*?x(\d+)/i).each do |count, gen, lanes|
      slots << {
        "count" => count.to_i,
        "generation" => gen,
        "lanes" => lanes.to_i
      }
    end

    # Fallback to old pattern
    if slots.empty?
      text.scan(/(\d+)\s*x?\s*PCIe?\s*([\d.]+)\s*x(\d+)/i).each do |count, gen, lanes|
        slots << {
          "count" => count.to_i,
          "generation" => gen,
          "lanes" => lanes.to_i
        }
      end
    end

    slots.uniq { |s| [ s["count"], s["generation"], s["lanes"] ] }
  end

  def extract_gpu_support(specs_text, full_text)
    text = specs_text.presence || full_text
    !!(text =~ /GPU|NVIDIA|AMD\s*Radeon|accelerator/i)
  end
end
