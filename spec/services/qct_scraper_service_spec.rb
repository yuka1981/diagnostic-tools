# frozen_string_literal: true

require "rails_helper"

RSpec.describe QctScraperService do
  # Disable rate limiting in tests for faster execution
  let(:service) { described_class.new(request_delay: 0) }

  describe "#sync_all" do
    # Main listing page shows category links
    let(:product_listing_html) do
      <<~HTML
        <html>
        <body>
          <div class="category-list">
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server">2U Servers</a>
          </div>
        </body>
        </html>
      HTML
    end

    # Category page shows product links
    let(:category_2u_html) do
      <<~HTML
        <html>
        <body>
          <h1>2U Rackmount Servers</h1>
          <div class="product-list">
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U">
              QuantaGrid D54Q-2U
            </a>
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-S74G-2U">
              QuantaGrid S74G-2U
            </a>
          </div>
        </body>
        </html>
      HTML
    end

    let(:product_page_html_d54q) do
      <<~HTML
        <html>
        <body>
          <h1 class="product-name">QuantaGrid D54Q-2U</h1>
          <div class="specs">
            <span class="form-factor">2U</span>
            <p>CPU: 2 Socket, 5th Gen Intel Xeon</p>
            <p>Memory: 32 DIMM slots, DDR5, up to 8192 GB max</p>
            <p>Storage: 24 x NVMe 2.5 drives</p>
            <p>PCIe: 4 x PCIe 5.0 x16 slots</p>
            <p>GPU accelerator support available</p>
          </div>
        </body>
        </html>
      HTML
    end

    let(:product_page_html_s74g) do
      <<~HTML
        <html>
        <body>
          <h1 class="product-name">QuantaGrid S74G-2U</h1>
          <div class="specs">
            <span class="form-factor">2U</span>
            <p>CPU: 2 Socket, AMD EPYC</p>
            <p>Memory: 24 DIMM slots, DDR5, up to 6144 GB max</p>
          </div>
        </body>
        </html>
      HTML
    end

    before do
      stub_request(:get, QctScraperService::BASE_URL)
        .to_return(status: 200, body: product_listing_html)
      stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server")
        .to_return(status: 200, body: category_2u_html)
      stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U")
        .to_return(status: 200, body: product_page_html_d54q)
      stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-S74G-2U")
        .to_return(status: 200, body: product_page_html_s74g)
    end

    it "returns a Result struct" do
      result = service.sync_all
      expect(result).to respond_to(:added_count)
      expect(result).to respond_to(:updated_count)
      expect(result).to respond_to(:errors)
    end

    context "when syncing new products" do
      it "creates new ServerProduct records" do
        expect { service.sync_all }.to change(ServerProduct, :count).by(2)
      end

      it "reports added count" do
        result = service.sync_all
        expect(result.added_count).to eq(2)
      end

      it "sets product attributes correctly" do
        service.sync_all
        product = ServerProduct.find_by(name: "QuantaGrid D54Q-2U")

        expect(product).to be_present
        expect(product.product_series).to eq("QuantaGrid")
        expect(product.form_factor).to eq("2U")
        expect(product.rack_height).to eq(2)
        expect(product.qct_product_url).to eq("https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U")
      end
    end

    context "when syncing existing products" do
      before do
        create(:server_product,
          name: "QuantaGrid D54Q-2U",
          qct_product_url: "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U",
          max_memory_gb: 1024) # Old value that should get updated
      end

      it "updates existing ServerProduct records" do
        result = service.sync_all
        expect(result.updated_count).to eq(1)
        expect(result.added_count).to eq(1) # S74G is new
      end

      it "updates last_synced_at" do
        service.sync_all
        product = ServerProduct.find_by(name: "QuantaGrid D54Q-2U")
        expect(product.last_synced_at).to be_within(1.second).of(Time.current)
      end
    end

    context "when encountering HTTP errors" do
      before do
        stub_request(:get, QctScraperService::BASE_URL)
          .to_return(status: 500)
      end

      it "captures errors in result" do
        result = service.sync_all
        expect(result.errors).not_to be_empty
      end

      it "returns zero counts on listing failure" do
        result = service.sync_all
        expect(result.added_count).to eq(0)
        expect(result.updated_count).to eq(0)
      end
    end

    context "when a single product page fails" do
      before do
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U")
          .to_return(status: 404)
      end

      it "continues processing other products" do
        result = service.sync_all
        expect(result.added_count).to eq(1) # S74G succeeds
        expect(result.errors.size).to eq(1) # D54Q fails
      end

      it "records error details" do
        result = service.sync_all
        error = result.errors.first
        expect(error[:url]).to include("D54Q")
        expect(error[:error]).to be_present
      end
    end
  end

  describe "#sync_product" do
    let(:product_page_html) do
      <<~HTML
        <html>
        <body>
          <h1>QuantaGrid D54Q-2U</h1>
          <p>Form Factor: 2U</p>
          <p>2 Socket, 5th Gen Intel Xeon Scalable</p>
          <p>Memory: 32 DIMM DDR5 up to 8192 GB maximum</p>
          <p>Storage: 24 x NVMe 2.5</p>
        </body>
        </html>
      HTML
    end

    let(:url) { "https://www.qct.io/product/index/Server/rackmount-server/QuantaGrid-D54Q-2U" }

    before do
      stub_request(:get, url)
        .to_return(status: 200, body: product_page_html)
    end

    it "creates a new product and returns :added" do
      result = service.sync_product(url)
      expect(result).to eq(:added)
      expect(ServerProduct.count).to eq(1)
    end

    context "when product already exists" do
      before do
        create(:server_product,
          name: "QuantaGrid D54Q-2U",
          qct_product_url: url)
      end

      it "updates existing product and returns :updated" do
        result = service.sync_product(url)
        expect(result).to eq(:updated)
        expect(ServerProduct.count).to eq(1)
      end
    end

    context "when HTTP request fails" do
      before do
        stub_request(:get, url).to_return(status: 500)
      end

      it "returns error message string" do
        result = service.sync_product(url)
        expect(result).to be_a(String)
        expect(result).to include("500")
      end
    end

    context "with product image" do
      let(:product_page_with_image_html) do
        <<~HTML
          <html>
          <body>
            <h1>QuantaGrid D54Q-2U</h1>
            <div class="image_block">
              <img src="/upload/website/product/images/server_image.png" class="img-responsive">
            </div>
            <p>Form Factor: 2U</p>
          </body>
          </html>
        HTML
      end

      let(:image_url) { "https://www.qct.io/upload/website/product/images/server_image.png" }
      let(:image_data) { File.read(Rails.root.join("spec/fixtures/files/test_image.png"), mode: "rb") rescue "\x89PNG\r\n\x1a\n" }

      before do
        stub_request(:get, url)
          .to_return(status: 200, body: product_page_with_image_html)
        stub_request(:get, image_url)
          .to_return(status: 200, body: image_data, headers: { "Content-Type" => "image/png" })
      end

      it "downloads and attaches the product image" do
        expect { service.sync_product(url) }.to change(ActiveStorage::Attachment, :count).by(1)

        product = ServerProduct.last
        expect(product.images).to be_attached
        expect(product.images.first.filename.to_s).to eq("server_image.png")
      end

      it "stores the source URL in image metadata" do
        service.sync_product(url)
        product = ServerProduct.last
        expect(product.images.first.blob.metadata["source_url"]).to eq(image_url)
      end

      it "skips image download if already attached with same source URL" do
        # First sync - should attach image
        service.sync_product(url)
        expect(ActiveStorage::Attachment.count).to eq(1)

        # Second sync - should skip image download (same source URL)
        service.sync_product(url)
        expect(ActiveStorage::Attachment.count).to eq(1)
      end

      context "when image download fails" do
        before do
          stub_request(:get, image_url).to_return(status: 404)
        end

        it "still creates the product successfully" do
          result = service.sync_product(url)
          expect(result).to eq(:added)
          expect(ServerProduct.count).to eq(1)
        end

        it "does not attach any image" do
          service.sync_product(url)
          product = ServerProduct.last
          expect(product.images).not_to be_attached
        end
      end
    end
  end

  describe "#parse_product_page" do
    it "extracts model name from h1 tag" do
      html = '<html><body><h1>QuantaGrid D54Q-2U</h1></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:name]).to eq("QuantaGrid D54Q-2U")
    end

    it "extracts model name from product-name class" do
      html = '<html><body><div class="product-name">QuantaPlex T41S-2U</div></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:name]).to eq("QuantaPlex T41S-2U")
    end

    it "extracts product series from model name" do
      html = '<html><body><h1>QuantaGrid D54Q-2U</h1></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:product_series]).to eq("QuantaGrid")
    end

    it "extracts form factor from model name" do
      html = '<html><body><h1>QuantaGrid D54Q-2U</h1></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:form_factor]).to eq("2U")
      expect(attrs[:rack_height]).to eq(2)
    end

    it "extracts socket count" do
      html = '<html><body><h1>Test Server</h1><p>2 Socket Intel Xeon</p></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:socket_count]).to eq(2)
    end

    it "extracts CPU generations for Intel Xeon" do
      html = '<html><body><h1>Test Server</h1><p>5th Gen Intel Xeon</p></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:cpu_generations]).to include("5th Gen Xeon")
    end

    it "extracts max memory in GB" do
      html = '<html><body><h1>Test Server</h1><p>up to 8192 GB max memory</p></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:max_memory_gb]).to eq(8192)
    end

    it "converts TB to GB for max memory" do
      html = '<html><body><h1>Test Server</h1><p>up to 8 TB maximum memory</p></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:max_memory_gb]).to eq(8192)
    end

    it "extracts DIMM slots" do
      html = '<html><body><h1>Test Server</h1><p>32 DIMM slots</p></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:dimm_slots]).to eq(32)
    end

    it "extracts memory types" do
      html = '<html><body><h1>Test Server</h1><p>DDR5 memory support</p></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:memory_types]).to include("DDR5")
    end

    it "extracts GPU support" do
      html = '<html><body><h1>Test Server</h1><p>NVIDIA GPU accelerator support</p></body></html>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:gpu_support]).to be true
    end

    it "sets qct_product_url from provided url" do
      html = '<html><body><h1>Test Server</h1></body></html>'
      attrs = service.send(:parse_product_page, html, "https://www.qct.io/product/test")
      expect(attrs[:qct_product_url]).to eq("https://www.qct.io/product/test")
    end

    context "image extraction" do
      it "prioritizes gallery/normal images (highest quality)" do
        html = <<~HTML
          <html>
          <body>
            <h1>QuantaGrid D54Q-2U</h1>
            <img src="/upload/website/product/icon/xeon-logo.png">
            <img src="/upload/website/product/gallery/normal/DSC04863.png">
            <img src="/upload/website/product/images/cover.png">
          </body>
          </html>
        HTML
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to eq("https://www.qct.io/upload/website/product/gallery/normal/DSC04863.png")
      end

      it "falls back to gallery/thumbnail if no normal gallery image" do
        html = <<~HTML
          <html>
          <body>
            <h1>Test Server</h1>
            <img src="/upload/website/product/gallery/thumbnail/DSC04863.png">
          </body>
          </html>
        HTML
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to eq("https://www.qct.io/upload/website/product/gallery/thumbnail/DSC04863.png")
      end

      it "extracts cover image from /product/images/ path" do
        html = <<~HTML
          <html>
          <body>
            <h1>QuantaGrid D52BM-2U</h1>
            <img src="/upload/website/product/images/D52BM-2U-cover_12345.png">
          </body>
          </html>
        HTML
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to eq("https://www.qct.io/upload/website/product/images/D52BM-2U-cover_12345.png")
      end

      it "extracts image from .image_block (listing page fallback)" do
        html = <<~HTML
          <html>
          <body>
            <h1>Test Server</h1>
            <div class="image_block">
              <img src="/some/other/path/server.jpg">
            </div>
          </body>
          </html>
        HTML
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to eq("https://www.qct.io/some/other/path/server.jpg")
      end

      it "skips icon images" do
        html = <<~HTML
          <html>
          <body>
            <h1>Test Server</h1>
            <img src="/upload/website/product/icon/xeon-logo.png">
          </body>
          </html>
        HTML
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to be_nil
      end

      it "skips media images" do
        html = <<~HTML
          <html>
          <body>
            <h1>Test Server</h1>
            <img src="/upload/media/product/diagram.png">
          </body>
          </html>
        HTML
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to be_nil
      end

      it "preserves absolute image URLs" do
        html = <<~HTML
          <html>
          <body>
            <h1>Test Server</h1>
            <img src="https://cdn.example.com/upload/website/product/gallery/normal/server.png">
          </body>
          </html>
        HTML
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to eq("https://cdn.example.com/upload/website/product/gallery/normal/server.png")
      end

      it "returns nil when no product image is found" do
        html = '<html><body><h1>Test Server</h1></body></html>'
        attrs = service.send(:parse_product_page, html, "https://example.com")
        expect(attrs[:image_url]).to be_nil
      end
    end

    context "with actual QCT website HTML format" do
      let(:qct_product_html) do
        <<~HTML
          <html>
          <body>
            <h1>QuantaGrid D52BQ-2U</h1>
            <div id="specifications">
              <div class="spec-section">
                <strong>Processor Family</strong>
                <span>Intel®Xeon® Processor Scalable Family</span>
              </div>
              <div class="spec-section">
                <strong>Number of Processors</strong>
                <span>2 Processors</span>
              </div>
              <div class="spec-section">
                <strong>Memory</strong>
                <ul>
                  <li>Total Slots: 24</li>
                  <li>Up to 3TB (128Gx24) of memory for RDIMM/LRDIMM</li>
                  <li>2933Mhz DDR4 RDIMM/LRDIMM</li>
                </ul>
              </div>
              <div class="spec-section">
                <strong>Storage</strong>
                <ul>
                  <li>(12) 3.5"/2.5" hot-plug SATA/SAS</li>
                  <li>(24) 2.5" hot-plug NVMe SSD</li>
                </ul>
              </div>
              <div class="spec-section">
                <strong>Expansion Slots</strong>
                <ul>
                  <li>(1) PCIe Gen3 x16 SAS mezzanine slot</li>
                  <li>(2) PCIe Gen3 x8 FHHL</li>
                  <li>(4) PCIe Gen3 x16 FHFL</li>
                </ul>
              </div>
              <div class="spec-section">
                <strong>Form Factor</strong>
                <span>2U</span>
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      it "extracts socket count from QCT format 'Number of Processors: 2 Processors'" do
        attrs = service.send(:parse_product_page, qct_product_html, "https://example.com")
        expect(attrs[:socket_count]).to eq(2)
      end

      it "extracts DIMM slots from QCT format 'Total Slots: 24'" do
        attrs = service.send(:parse_product_page, qct_product_html, "https://example.com")
        expect(attrs[:dimm_slots]).to eq(24)
      end

      it "extracts max memory from QCT format 'Up to 3TB'" do
        attrs = service.send(:parse_product_page, qct_product_html, "https://example.com")
        expect(attrs[:max_memory_gb]).to eq(3072) # 3TB = 3072GB
      end

      it "extracts memory types from QCT format" do
        attrs = service.send(:parse_product_page, qct_product_html, "https://example.com")
        expect(attrs[:memory_types]).to include("DDR4")
      end

      it "extracts drive bays from QCT format '(12) 3.5\"/2.5\" hot-plug SATA/SAS'" do
        attrs = service.send(:parse_product_page, qct_product_html, "https://example.com")
        expect(attrs[:drive_bays]).to be_present
        expect(attrs[:drive_bays].any? { |b| b["count"] == 12 && b["type"] == "SATA" }).to be true
      end

      it "extracts NVMe drive bays from QCT format" do
        attrs = service.send(:parse_product_page, qct_product_html, "https://example.com")
        expect(attrs[:drive_bays].any? { |b| b["count"] == 24 && b["type"] == "NVME" }).to be true
      end

      it "extracts PCIe slots from QCT format '(1) PCIe Gen3 x16'" do
        attrs = service.send(:parse_product_page, qct_product_html, "https://example.com")
        expect(attrs[:pcie_slots]).to be_present
        # Should find x16 slots
        expect(attrs[:pcie_slots].any? { |s| s["lanes"] == 16 }).to be true
      end
    end

    context "when specifications are in TABLE format (no #specifications div)" do
      # This tests the table-based extraction strategy for real QCT pages
      # where specs are in tables without a dedicated #specifications container
      let(:table_based_specs_html) do
        <<~HTML
          <html>
          <body>
            <h1>QuantaGrid D54Q-2U</h1>
            <nav>
              <a href="#overview">Overview</a>
              <a href="#specifications">Specifications</a>
            </nav>
            <table class="product-specs">
              <tr>
                <td>Processor Type</td>
                <td>5th/4th Gen Intel® Xeon® Scalable Processors</td>
              </tr>
              <tr>
                <td>Number of Processors</td>
                <td>2 Processors</td>
              </tr>
              <tr>
                <td>Memory</td>
                <td>Total Slots: 32, Up to 8TB DDR5</td>
              </tr>
              <tr>
                <td>Storage</td>
                <td>(24) 2.5" hot-plug NVMe SSD, (4) 3.5" SATA</td>
              </tr>
              <tr>
                <td>Expansion Slot</td>
                <td>(2) PCIe Gen5 x16, (4) PCIe Gen4 x8</td>
              </tr>
              <tr>
                <td>Form Factor</td>
                <td>2U Rackmount</td>
              </tr>
            </table>
          </body>
          </html>
        HTML
      end

      it "extracts specifications from TABLE elements when no #specifications div exists" do
        attrs = service.send(:parse_product_page, table_based_specs_html, "https://example.com")

        expect(attrs[:socket_count]).to eq(2)
        expect(attrs[:dimm_slots]).to eq(32)
        expect(attrs[:max_memory_gb]).to eq(8192) # 8TB
        expect(attrs[:memory_types]).to include("DDR5")
        expect(attrs[:drive_bays]).to be_present
        expect(attrs[:pcie_slots]).to be_present
      end

      it "extracts CPU generation from table-based specs" do
        attrs = service.send(:parse_product_page, table_based_specs_html, "https://example.com")
        expect(attrs[:cpu_generations]).to include("5th Gen Xeon")
        expect(attrs[:cpu_generations]).to include("4th Gen Xeon")
      end
    end
  end

  describe "#fetch_product_listing" do
    context "with pagination support" do
      let(:main_listing_page1_html) do
        <<~HTML
          <html>
          <body>
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server">2U Servers</a>
            <a href="?page=2">Next</a>
          </body>
          </html>
        HTML
      end

      let(:main_listing_page2_html) do
        <<~HTML
          <html>
          <body>
            <a href="/product/index/Server/rackmount-server/4U-Rackmount-Server">4U Servers</a>
          </body>
          </html>
        HTML
      end

      let(:category_2u_page1_html) do
        <<~HTML
          <html>
          <body>
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U">D54Q</a>
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D55Q-2U">D55Q</a>
            <a href="?page=2">Next</a>
          </body>
          </html>
        HTML
      end

      let(:category_2u_page2_html) do
        <<~HTML
          <html>
          <body>
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-S74G-2U">S74G</a>
          </body>
          </html>
        HTML
      end

      let(:category_4u_html) do
        <<~HTML
          <html>
          <body>
            <a href="/product/index/Server/rackmount-server/4U-Rackmount-Server/QuantaGrid-D54X-4U">D54X</a>
          </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, QctScraperService::BASE_URL)
          .to_return(status: 200, body: main_listing_page1_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server?page=2")
          .to_return(status: 200, body: main_listing_page2_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server")
          .to_return(status: 200, body: category_2u_page1_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server?page=2")
          .to_return(status: 200, body: category_2u_page2_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/4U-Rackmount-Server")
          .to_return(status: 200, body: category_4u_html)
      end

      it "fetches products from all pages of main listing" do
        urls = service.send(:fetch_product_listing)
        # Should find 4U category from page 2
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/4U-Rackmount-Server/QuantaGrid-D54X-4U")
      end

      it "fetches products from all pages within each category" do
        urls = service.send(:fetch_product_listing)
        # Should find all 3 products from 2U category (2 from page 1, 1 from page 2)
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U")
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D55Q-2U")
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-S74G-2U")
      end

      it "collects products from all categories across all pages" do
        urls = service.send(:fetch_product_listing)
        # Total: 3 from 2U category + 1 from 4U category = 4 products
        expect(urls.size).to eq(4)
      end
    end

    context "with two-stage scraping (real QCT site structure)" do
      let(:main_listing_html) do
        <<~HTML
          <html>
          <body>
            <div class="category-nav">
              <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server">1U Servers</a>
              <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server">2U Servers</a>
              <a href="/product/index/Server/rackmount-server/Edge-Server">Edge Servers</a>
            </div>
            <div class="featured-products">
              <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X-1U">Featured: D54X</a>
            </div>
          </body>
          </html>
        HTML
      end

      let(:category_1u_html) do
        <<~HTML
          <html>
          <body>
            <h1>1U Rackmount Servers</h1>
            <div class="product-list">
              <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X-1U">QuantaGrid D54X-1U</a>
              <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-S55R-1U">QuantaGrid S55R-1U</a>
            </div>
          </body>
          </html>
        HTML
      end

      let(:category_2u_html) do
        <<~HTML
          <html>
          <body>
            <h1>2U Rackmount Servers</h1>
            <div class="product-list">
              <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U">QuantaGrid D54Q-2U</a>
            </div>
          </body>
          </html>
        HTML
      end

      let(:category_edge_html) do
        <<~HTML
          <html>
          <body>
            <h1>Edge Servers</h1>
            <div class="product-list">
              <a href="/product/index/Server/rackmount-server/Edge-Server/QuantaEdge-EX100-B1">QuantaEdge EX100</a>
            </div>
          </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, QctScraperService::BASE_URL)
          .to_return(status: 200, body: main_listing_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server")
          .to_return(status: 200, body: category_1u_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server")
          .to_return(status: 200, body: category_2u_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/Edge-Server")
          .to_return(status: 200, body: category_edge_html)
      end

      it "collects product URLs from all category pages" do
        urls = service.send(:fetch_product_listing)

        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X-1U")
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-S55R-1U")
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server/QuantaGrid-D54Q-2U")
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/Edge-Server/QuantaEdge-EX100-B1")
      end

      it "excludes category URLs from final result" do
        urls = service.send(:fetch_product_listing)

        # Category URLs have 4 path segments, should be excluded
        expect(urls).not_to include("https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server")
        expect(urls).not_to include("https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server")
        expect(urls).not_to include("https://www.qct.io/product/index/Server/rackmount-server/Edge-Server")
      end

      it "removes duplicate product URLs" do
        urls = service.send(:fetch_product_listing)
        # D54X appears in main listing and 1U category, should only appear once
        d54x_urls = urls.select { |u| u.include?("D54X") }
        expect(d54x_urls.size).to eq(1)
      end
    end

    context "when pages contain links back to base URL or non-product URLs" do
      # Regression test: previously, any URL that wasn't a category (5 segments) was
      # treated as a product, including the base page URL (4 segments). This caused
      # invalid model names like "Rackmount Server" to be created.

      let(:main_listing_with_invalid_urls) do
        <<~HTML
          <html>
          <body>
            <nav>
              <!-- Back link to main page (4 segments - should be filtered out) -->
              <a href="/product/index/Server/rackmount-server/">Rackmount Server</a>
              <!-- Breadcrumb link (3 segments - should be filtered out) -->
              <a href="/product/index/Server/">All Servers</a>
            </nav>
            <div class="category-nav">
              <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server">1U Servers</a>
            </div>
          </body>
          </html>
        HTML
      end

      let(:category_1u_with_back_link) do
        <<~HTML
          <html>
          <body>
            <nav>
              <!-- Back link to main listing (4 segments - should be filtered out) -->
              <a href="/product/index/Server/rackmount-server/">Back to All Rackmount</a>
              <!-- Back link to category (5 segments - should be filtered out) -->
              <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server/">1U Category</a>
            </nav>
            <div class="product-list">
              <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X-1U">QuantaGrid D54X-1U</a>
            </div>
          </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, QctScraperService::BASE_URL)
          .to_return(status: 200, body: main_listing_with_invalid_urls)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server")
          .to_return(status: 200, body: category_1u_with_back_link)
      end

      it "filters out URLs that are not exactly 6 segments (product pages)" do
        urls = service.send(:fetch_product_listing)

        # Should only include valid product URLs (6 segments)
        expect(urls).to eq([ "https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X-1U" ])
      end

      it "does not include base page URL or other non-product URLs" do
        urls = service.send(:fetch_product_listing)

        # These should all be filtered out (wrong segment count)
        expect(urls).not_to include("https://www.qct.io/product/index/Server/rackmount-server/")
        expect(urls).not_to include("https://www.qct.io/product/index/Server/")
      end
    end

    context "when category page fails" do
      let(:main_listing_html) do
        <<~HTML
          <html>
          <body>
            <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server">1U Servers</a>
            <a href="/product/index/Server/rackmount-server/2U-Rackmount-Server">2U Servers</a>
          </body>
          </html>
        HTML
      end

      let(:category_1u_html) do
        <<~HTML
          <html>
          <body>
            <a href="/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X-1U">D54X</a>
          </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, QctScraperService::BASE_URL)
          .to_return(status: 200, body: main_listing_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server")
          .to_return(status: 200, body: category_1u_html)
        stub_request(:get, "https://www.qct.io/product/index/Server/rackmount-server/2U-Rackmount-Server")
          .to_return(status: 500)
      end

      it "continues processing other categories when one fails" do
        urls = service.send(:fetch_product_listing)
        expect(urls).to include("https://www.qct.io/product/index/Server/rackmount-server/1U-Rackmount-Server/QuantaGrid-D54X-1U")
      end
    end
  end
end
