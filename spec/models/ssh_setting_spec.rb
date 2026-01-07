# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshSetting, type: :model do
  describe ".current" do
    it "returns the first record or creates one" do
      expect(described_class.count).to eq(0)
      setting = described_class.current
      expect(setting).to be_persisted
      expect(described_class.current).to eq(setting)
      expect(described_class.count).to eq(1)
    end

    it "defaults bastion_port to 22" do
      expect(described_class.current.bastion_port).to eq(22)
    end
  end

  describe "validations" do
    it "validates bastion_port range" do
      setting = described_class.current
      setting.bastion_port = 70000
      expect(setting).not_to be_valid
      setting.bastion_port = 22
      expect(setting).to be_valid
    end
  end
end
