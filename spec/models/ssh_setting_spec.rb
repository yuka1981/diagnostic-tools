# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshSetting, type: :model do
  describe ".current" do
    it "returns existing record or creates one" do
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

    describe "server_url" do
      it "allows blank server_url" do
        setting = described_class.new(server_url: nil)
        expect(setting).to be_valid
      end

      it "allows valid base URLs" do
        %w[
          https://example.com
          http://example.com
          https://hpc.example.com
          https://example.com:3000
          https://example.com/
        ].each do |url|
          setting = described_class.new(server_url: url)
          expect(setting).to be_valid, "Expected #{url} to be valid"
        end
      end

      it "rejects URLs with path components" do
        %w[
          https://example.com/nodes
          https://example.com/api/v1
          http://example.com/dashboard
        ].each do |url|
          setting = described_class.new(server_url: url)
          expect(setting).not_to be_valid, "Expected #{url} to be invalid"
          expect(setting.errors[:server_url]).to include("must be a base URL without path (e.g., https://example.com, not https://example.com/nodes)")
        end
      end

      it "rejects URLs with invalid schemes" do
        setting = described_class.new(server_url: "ftp://example.com")
        expect(setting).not_to be_valid
        expect(setting.errors[:server_url]).to include("must use http or https scheme")
      end

      it "rejects invalid URLs" do
        setting = described_class.new(server_url: "not a url")
        expect(setting).not_to be_valid
        expect(setting.errors[:server_url]).to include("is not a valid URL")
      end
    end
  end
end
