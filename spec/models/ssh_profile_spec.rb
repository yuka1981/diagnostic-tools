# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshProfile, type: :model do
  describe "validations" do
    subject { build(:ssh_profile) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_presence_of(:ssh_connect_method) }
    it { is_expected.to validate_numericality_of(:ssh_port).only_integer.is_greater_than(0).is_less_than(65536) }
    it { is_expected.to validate_numericality_of(:jump_port).only_integer.is_greater_than(0).is_less_than(65536).allow_nil }
  end

  describe "enums" do
    it "defines ssh_connect_method enum" do
      expect(SshProfile.ssh_connect_methods).to eq({
        "global_bastion" => 0,
        "custom_bastion" => 1,
        "direct" => 2
      })
    end
  end

  describe "associations" do
    it "defines has_many :nodes association" do
      association = SshProfile.reflect_on_association(:nodes)
      expect(association).not_to be_nil
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:nullify)
    end
  end

  describe "factory" do
    it "creates a valid ssh_profile" do
      expect(build(:ssh_profile)).to be_valid
    end

    it "creates valid custom_bastion profile" do
      profile = build(:ssh_profile, :custom_bastion)
      expect(profile).to be_valid
      expect(profile.jump_host).to eq("bastion.example.com")
    end
  end

  describe "#display_connection_method" do
    it "returns human-readable connection method" do
      profile = build(:ssh_profile, :global_bastion)
      expect(profile.display_connection_method).to eq("Global Bastion")
    end
  end
end
