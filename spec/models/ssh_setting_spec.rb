# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshSetting, type: :model do
  describe ".current" do
    it "returns existing record or creates one" do
      described_class.delete_all # Ensure no record exists
      expect { described_class.current }.to change(described_class, :count).by(1)
      expect { described_class.current }.not_to change(described_class, :count)
    end

    it "sets default values" do
      setting = described_class.current
      expect(setting.bastion_port).to eq(22)
      expect(setting.default_agent_path).to eq("/usr/local/bin/hpc-agent")
    end
  end

  describe "validations" do
    it "validates bastion_port range" do
      setting = described_class.new
      setting.bastion_port = 70_000
      expect(setting).not_to be_valid
      expect(setting.errors[:bastion_port]).to be_present

      setting.bastion_port = 22
      expect(setting).to be_valid
    end

    it "allows blank bastion_port" do
      setting = described_class.new(bastion_port: nil)
      expect(setting).to be_valid
    end
  end
end
