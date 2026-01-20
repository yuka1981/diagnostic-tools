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
    # Note: Rack model will be created in Task 2
    # This test will be enabled once Rack model exists
    it "has many racks with dependent destroy" do
      skip "Rack model not yet created (Task 2)"
      is_expected.to have_many(:racks).dependent(:destroy)
    end
  end

  describe "factory" do
    it "creates a valid site" do
      site = build(:site)
      expect(site).to be_valid
    end
  end
end
