# frozen_string_literal: true

require "rails_helper"

RSpec.describe Site, type: :model do
  describe "validations" do
    subject { build(:site) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "associations" do
    it { is_expected.to have_many(:server_racks).dependent(:destroy) }
  end

  describe "factory" do
    it "creates a valid site" do
      site = build(:site)
      expect(site).to be_valid
    end
  end
end
