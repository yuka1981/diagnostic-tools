require "rails_helper"

RSpec.describe ServerProduct, type: :model do
  describe "validations" do
    subject { build(:server_product) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "associations" do
    it { is_expected.to have_many(:nodes) }
    it { is_expected.to have_many_attached(:images) }
  end

  describe "factory" do
    it "creates a valid server product" do
      product = build(:server_product)
      expect(product).to be_valid
    end
  end

  describe "scopes" do
    let!(:quantagrid) { create(:server_product, product_series: "QuantaGrid") }
    let!(:quantaplex) { create(:server_product, product_series: "QuantaPlex") }
    let!(:one_u) { create(:server_product, form_factor: "1U") }
    let!(:two_u) { create(:server_product, form_factor: "2U") }

    describe ".by_series" do
      it "filters by product series" do
        expect(ServerProduct.by_series("QuantaGrid")).to include(quantagrid)
        expect(ServerProduct.by_series("QuantaGrid")).not_to include(quantaplex)
      end
    end

    describe ".by_form_factor" do
      it "filters by form factor" do
        expect(ServerProduct.by_form_factor("1U")).to include(one_u)
        expect(ServerProduct.by_form_factor("1U")).not_to include(two_u)
      end
    end
  end

  describe "#rack_height_from_form_factor" do
    it "extracts numeric height from form factor" do
      product = build(:server_product, form_factor: "2U")
      expect(product.rack_height).to eq(2)
    end
  end

  describe "#thumbnail_variant" do
    let(:product) { create(:server_product) }

    context "with attached image" do
      before do
        product.images.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/test_server.png")),
          filename: "test_server.png",
          content_type: "image/png"
        )
      end

      it "returns a variant with resize_to_fill transformation" do
        variant = product.thumbnail_variant
        expect(variant).to be_a(ActiveStorage::VariantWithRecord)
        expect(variant.variation.transformations).to include(resize_to_fill: [ 48, 48 ])
      end
    end

    context "without attached image" do
      it "returns nil" do
        expect(product.thumbnail_variant).to be_nil
      end
    end
  end

  describe "#preprocess_image_variants!" do
    let(:product) { create(:server_product) }

    before do
      product.images.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test_server.png")),
        filename: "test_server.png",
        content_type: "image/png"
      )
    end

    it "processes all image variants" do
      expect { product.preprocess_image_variants! }.not_to raise_error
      # Verify variant was processed by checking the variant record exists
      variant = product.images.first.variant(resize_to_fill: [ 48, 48 ]).processed
      expect(variant.key).to be_present
    end
  end
end
