require "rails_helper"

RSpec.describe MlcInstallation, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_many(:mlc_installation_nodes).dependent(:destroy) }
    it { is_expected.to have_many(:nodes).through(:mlc_installation_nodes) }
  end

  describe "enums" do
    it do
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, running: 1, completed: 2, failed: 3, cancelled: 4)
        .with_default(:pending)
    end

    it do
      is_expected.to define_enum_for(:source_type)
        .with_values(upload: 0, shared_path: 1)
        .with_default(:upload)
    end

    it do
      is_expected.to define_enum_for(:failure_mode)
        .with_values(stop_on_first: 0, continue_on_failure: 1)
        .with_default(:stop_on_first)
    end
  end

  describe "validations" do
    it "validates uniqueness of uuid" do
      create(:mlc_installation)
      is_expected.to validate_uniqueness_of(:uuid)
    end

    it "requires uuid after callback runs" do
      installation = MlcInstallation.new
      installation.valid?
      expect(installation.errors[:uuid]).to be_empty
    end
  end

  describe "callbacks" do
    it "generates uuid before validation on create" do
      installation = build(:mlc_installation, uuid: nil)
      installation.valid?
      expect(installation.uuid).to be_present
    end
  end

  describe "#progress_percentage" do
    let(:installation) { create(:mlc_installation) }

    context "with no nodes" do
      it "returns 0" do
        expect(installation.progress_percentage).to eq(0)
      end
    end

    context "with completed nodes" do
      before do
        create(:mlc_installation_node, mlc_installation: installation, status: :success)
        create(:mlc_installation_node, mlc_installation: installation, status: :pending)
      end

      it "returns percentage of completed nodes" do
        expect(installation.progress_percentage).to eq(50)
      end
    end
  end
end
