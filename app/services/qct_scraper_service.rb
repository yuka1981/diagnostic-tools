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

    product = ServerProduct.find_or_initialize_by(qct_product_url: url)
    is_new = product.new_record?

    product.assign_attributes(attrs)
    product.last_synced_at = Time.current
    product.save!

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

  def fetch_product_listing
    rate_limit
    html = fetch_page(BASE_URL)
    doc = Nokogiri::HTML(html)

    # Collect all rackmount-server URLs from main page (including paginated pages)
    all_urls = fetch_all_pages_urls(BASE_URL, doc)

    # Separate category URLs from product URLs
    category_urls, product_urls = all_urls.partition { |url| category_url?(url) }

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

    # Fetch products from all pages of this category
    fetch_all_pages_urls(category_url, doc).reject { |url| category_url?(url) }
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
    # Count path segments to determine if URL is a category or product
    # /product/index/Server/rackmount-server/1U-Rackmount-Server = 4 segments (category)
    # /product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X = 5 segments (product)
    path = URI.parse(url).path
    segments = path.split("/").reject(&:empty?)
    segments.size == CATEGORY_PATH_SEGMENTS
  end

  def parse_product_page(html, url)
    doc = Nokogiri::HTML(html)

    model_name = extract_model_name(doc)
    product_series = extract_series(model_name)
    form_factor = extract_form_factor(doc, model_name)
    rack_height = form_factor&.match(/(\d+)U/i)&.captures&.first&.to_i || 1

    {
      name: model_name,
      product_series: product_series,
      form_factor: form_factor,
      rack_height: rack_height,
      qct_product_url: url,
      cpu_generations: extract_cpu_generations(doc),
      socket_count: extract_socket_count(doc),
      max_memory_gb: extract_max_memory(doc),
      dimm_slots: extract_dimm_slots(doc),
      memory_types: extract_memory_types(doc),
      drive_bays: extract_drive_bays(doc),
      pcie_slots: extract_pcie_slots(doc),
      gpu_support: extract_gpu_support(doc)
    }.compact
  end

  def extract_model_name(doc)
    # Try various selectors for product name
    name_element = doc.at_css("h1, .product-name, .product-title")
    name_element&.text&.strip
  end

  def extract_series(model_name)
    return nil unless model_name

    %w[QuantaGrid QuantaPlex QuantaMesh QuantaEdge].find { |s| model_name.include?(s) }
  end

  def extract_form_factor(doc, model_name)
    # First try to extract from model name (e.g., "D54Q-2U")
    ff_match = model_name&.match(/(\d+U)/i)
    return ff_match[1].upcase if ff_match

    # Fallback to page text
    doc.text[/Form Factor[:\s]*(\d+U)/i, 1]&.upcase
  end

  def extract_cpu_generations(doc)
    cpu_text = doc.text

    generations = []
    generations << "5th Gen Xeon" if cpu_text =~ /5th\s*Gen.*Xeon|Emerald\s*Rapids/i
    generations << "4th Gen Xeon" if cpu_text =~ /4th\s*Gen.*Xeon|Sapphire\s*Rapids/i
    generations << "3rd Gen Xeon" if cpu_text =~ /3rd\s*Gen.*Xeon|Ice\s*Lake/i
    generations
  end

  def extract_socket_count(doc)
    doc.text[/(\d+)\s*Socket/i, 1]&.to_i
  end

  def extract_max_memory(doc)
    # Match patterns like "8192 GB max" or "8 TB maximum"
    mem_match = doc.text[/(\d+)\s*(TB|GB)\s*(?:max|maximum)/i]
    return nil unless mem_match

    value = mem_match[/(\d+)/, 1].to_i
    unit = mem_match[/(TB|GB)/i, 1]
    unit&.upcase == "TB" ? value * 1024 : value
  end

  def extract_dimm_slots(doc)
    doc.text[/(\d+)\s*DIMM/i, 1]&.to_i
  end

  def extract_memory_types(doc)
    types = []
    types << "DDR5" if doc.text =~ /DDR5/i
    types << "DDR4" if doc.text =~ /DDR4/i
    types
  end

  def extract_drive_bays(doc)
    bays = []
    doc.text.scan(/(\d+)\s*x?\s*(NVMe|SAS|SATA|SSD|HDD)\s*([\d.]+)?/i).each do |count, type, form_factor|
      bays << {
        "count" => count.to_i,
        "type" => type.upcase,
        "form_factor" => form_factor || "2.5"
      }
    end
    bays.uniq
  end

  def extract_pcie_slots(doc)
    slots = []
    doc.text.scan(/(\d+)\s*x?\s*PCIe?\s*([\d.]+)\s*x(\d+)/i).each do |count, gen, lanes|
      slots << {
        "count" => count.to_i,
        "generation" => gen,
        "lanes" => lanes.to_i
      }
    end
    slots.uniq
  end

  def extract_gpu_support(doc)
    !!(doc.text =~ /GPU|NVIDIA|AMD\s*Radeon|accelerator/i)
  end
end
