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

    it "sets BMC default values" do
      described_class.delete_all
      setting = described_class.current
      expect(setting.bmc_sensor_polling_interval).to eq(5)
      expect(setting.bmc_collection_enabled).to be(false)
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

    describe "bmc_sensor_polling_interval" do
      it "allows valid polling intervals (1, 3, 5)" do
        [ 1, 3, 5 ].each do |interval|
          setting = described_class.new(bmc_sensor_polling_interval: interval)
          expect(setting).to be_valid, "Expected #{interval} to be valid"
        end
      end

      it "rejects invalid polling intervals" do
        [ 0, 2, 4, 6, 10, -1 ].each do |interval|
          setting = described_class.new(bmc_sensor_polling_interval: interval)
          expect(setting).not_to be_valid, "Expected #{interval} to be invalid"
          expect(setting.errors[:bmc_sensor_polling_interval]).to be_present
        end
      end

      it "allows nil polling interval" do
        setting = described_class.new(bmc_sensor_polling_interval: nil)
        expect(setting).to be_valid
      end
    end

    describe "bmc_collection_enabled" do
      it "accepts boolean values" do
        setting = described_class.new(bmc_collection_enabled: true)
        expect(setting).to be_valid

        setting.bmc_collection_enabled = false
        expect(setting).to be_valid
      end
    end

    describe "prometheus_pushgateway_url" do
      it "allows blank prometheus_pushgateway_url" do
        setting = described_class.new(prometheus_pushgateway_url: nil)
        expect(setting).to be_valid

        setting.prometheus_pushgateway_url = ""
        expect(setting).to be_valid
      end

      it "allows valid URLs" do
        %w[
          http://localhost:9091
          https://pushgateway.example.com
          http://prometheus-pushgateway:9091
          https://metrics.example.com:9091
        ].each do |url|
          setting = described_class.new(prometheus_pushgateway_url: url)
          expect(setting).to be_valid, "Expected #{url} to be valid"
        end
      end

      it "rejects URLs with invalid schemes" do
        setting = described_class.new(prometheus_pushgateway_url: "ftp://example.com")
        expect(setting).not_to be_valid
        expect(setting.errors[:prometheus_pushgateway_url]).to include("must use http or https scheme")
      end

      it "rejects invalid URLs" do
        setting = described_class.new(prometheus_pushgateway_url: "not a url")
        expect(setting).not_to be_valid
        expect(setting.errors[:prometheus_pushgateway_url]).to include("is not a valid URL")
      end
    end

    describe "prometheus_url" do
      it "allows blank prometheus_url" do
        setting = described_class.new(prometheus_url: nil)
        expect(setting).to be_valid

        setting.prometheus_url = ""
        expect(setting).to be_valid
      end

      it "allows valid URLs" do
        %w[
          http://localhost:9090
          https://prometheus.example.com
          http://prometheus:9090
          https://metrics.example.com:9090
        ].each do |url|
          setting = described_class.new(prometheus_url: url)
          expect(setting).to be_valid, "Expected #{url} to be valid"
        end
      end

      it "rejects URLs with invalid schemes" do
        setting = described_class.new(prometheus_url: "ftp://example.com")
        expect(setting).not_to be_valid
        expect(setting.errors[:prometheus_url]).to include("must use http or https scheme")
      end

      it "rejects invalid URLs" do
        setting = described_class.new(prometheus_url: "not a url")
        expect(setting).not_to be_valid
        expect(setting.errors[:prometheus_url]).to include("is not a valid URL")
      end
    end
  end
end
