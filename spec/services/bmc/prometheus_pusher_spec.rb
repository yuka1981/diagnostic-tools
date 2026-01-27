# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::PrometheusPusher do
  describe ".call" do
    let(:node) { create(:node, hostname: "test-node-001") }
    let(:sensors) do
      [
        { name: "CPU Temp", value: 45.5, unit: "Celsius", status: "OK" },
        { name: "System Fan 1", value: 3200, unit: "RPM", status: "OK" },
        { name: "Power Supply", value: 250, unit: "Watts", status: "Warning" },
        { name: "Main Voltage", value: 12.1, unit: "Volts", status: "OK" },
        { name: "Current Draw", value: 5.5, unit: "Amps", status: "Critical" }
      ]
    end
    let(:pushgateway_url) { "http://pushgateway.example.com:9091" }

    before do
      ssh_setting = SshSetting.current
      ssh_setting.update!(prometheus_pushgateway_url: pushgateway_url)
    end

    subject(:result) do
      described_class.call(node_id: node.id, sensors: sensors)
    end

    context "when successful" do
      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns a success result" do
        expect(result.success?).to be true
      end

      it "pushes metrics to Pushgateway" do
        result
        expect(
          a_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
        ).to have_been_made.once
      end

      it "formats metrics with correct content" do
        result
        expect(
          a_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
            .with { |req| req.body.include?('qis_bmc_temperature_celsius{node="test-node-001",sensor="CPU Temp"} 45.5') }
        ).to have_been_made.once
      end

      it "includes sensor status metrics" do
        result
        expect(
          a_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
            .with { |req| req.body.include?('qis_bmc_sensor_status{node="test-node-001",sensor="CPU Temp",status="OK"} 0') }
        ).to have_been_made.once
      end
    end

    context "when node is not found" do
      subject(:result) do
        described_class.call(node_id: 999_999, sensors: sensors)
      end

      it "returns a failure result" do
        expect(result.success?).to be false
      end

      it "returns appropriate error message" do
        expect(result.error).to eq("Node not found")
      end
    end

    context "when finding node by uuid" do
      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      subject(:result) do
        described_class.call(node_id: node.uuid, sensors: sensors)
      end

      it "returns a success result" do
        expect(result.success?).to be true
      end
    end

    context "when finding node by hostname" do
      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      subject(:result) do
        described_class.call(node_id: node.hostname, sensors: sensors)
      end

      it "returns a success result" do
        expect(result.success?).to be true
      end
    end

    context "when pushgateway URL is not configured" do
      before do
        SshSetting.current.update!(prometheus_pushgateway_url: nil)
      end

      it "returns a failure result" do
        expect(result.success?).to be false
      end

      it "returns appropriate error message" do
        expect(result.error).to eq("Pushgateway URL not configured")
      end
    end

    context "when pushgateway URL is blank" do
      before do
        SshSetting.current.update!(prometheus_pushgateway_url: "")
      end

      it "returns a failure result" do
        expect(result.success?).to be false
      end

      it "returns appropriate error message" do
        expect(result.error).to eq("Pushgateway URL not configured")
      end
    end

    context "when Pushgateway returns an error" do
      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 500, body: "Internal Server Error", headers: {})
      end

      it "returns a failure result" do
        expect(result.success?).to be false
      end

      it "returns error with response code and body" do
        expect(result.error).to eq("Pushgateway returned 500: Internal Server Error")
      end
    end

    context "when Pushgateway connection fails" do
      before do
        stub_request(:post, "http://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_timeout
      end

      it "returns a failure result" do
        expect(result.success?).to be false
      end

      it "returns error message" do
        expect(result.error).to be_present
      end
    end

    describe "metric name mapping" do
      before do
        stub_request(:post, %r{pushgateway\.example\.com})
          .to_return(status: 200, body: "", headers: {})
      end

      it "maps celsius to temperature metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp", value: 45, unit: "celsius", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_temperature_celsius") }
        ).to have_been_made.once
      end

      it "maps degrees c to temperature metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp", value: 45, unit: "degrees c", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_temperature_celsius") }
        ).to have_been_made.once
      end

      it "maps c to temperature metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp", value: 45, unit: "C", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_temperature_celsius") }
        ).to have_been_made.once
      end

      it "maps rpm to fan metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Fan", value: 3000, unit: "RPM", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_fan_rpm") }
        ).to have_been_made.once
      end

      it "maps watts to power metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Power", value: 200, unit: "Watts", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_power_watts") }
        ).to have_been_made.once
      end

      it "maps w to power metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Power", value: 200, unit: "W", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_power_watts") }
        ).to have_been_made.once
      end

      it "maps volts to voltage metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Voltage", value: 12, unit: "Volts", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_voltage_volts") }
        ).to have_been_made.once
      end

      it "maps v to voltage metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Voltage", value: 12, unit: "V", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_voltage_volts") }
        ).to have_been_made.once
      end

      it "maps amps to current metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Current", value: 5, unit: "Amps", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_current_amps") }
        ).to have_been_made.once
      end

      it "maps a to current metric" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Current", value: 5, unit: "A", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?("qis_bmc_current_amps") }
        ).to have_been_made.once
      end

      it "skips sensors with unknown unit types" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Unknown", value: 100, unit: "frobinators", status: "OK" } ])
        expect(result.success?).to be true
      end
    end

    describe "status value conversion" do
      before do
        stub_request(:post, %r{pushgateway\.example\.com})
          .to_return(status: 200, body: "", headers: {})
      end

      it "converts OK status to 0" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp", value: 45, unit: "Celsius", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?('status="OK"} 0') }
        ).to have_been_made.once
      end

      it "converts Warning status to 1" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp", value: 45, unit: "Celsius", status: "Warning" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?('status="Warning"} 1') }
        ).to have_been_made.once
      end

      it "converts Critical status to 2" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp", value: 45, unit: "Celsius", status: "Critical" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?('status="Critical"} 2') }
        ).to have_been_made.once
      end

      it "converts unknown status to 0" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp", value: 45, unit: "Celsius", status: "Unknown" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?('status="Unknown"} 0') }
        ).to have_been_made.once
      end
    end

    describe "label escaping" do
      before do
        stub_request(:post, %r{pushgateway\.example\.com})
          .to_return(status: 200, body: "", headers: {})
      end

      it "escapes backslashes in sensor names" do
        result = described_class.call(node_id: node.id, sensors: [ { name: 'Temp\\Path', value: 45, unit: "Celsius", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?('sensor="Temp\\\\Path"') }
        ).to have_been_made.once
      end

      it "escapes double quotes in sensor names" do
        result = described_class.call(node_id: node.id, sensors: [ { name: 'Temp"Quoted"', value: 45, unit: "Celsius", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?('sensor="Temp\\"Quoted\\""') }
        ).to have_been_made.once
      end

      it "escapes newlines in sensor names" do
        result = described_class.call(node_id: node.id, sensors: [ { name: "Temp\nLine", value: 45, unit: "Celsius", status: "OK" } ])
        expect(result.success?).to be true
        expect(
          a_request(:post, %r{pushgateway\.example\.com})
            .with { |req| req.body.include?('sensor="Temp\\nLine"') }
        ).to have_been_made.once
      end
    end

    context "when sensors is nil" do
      subject(:result) do
        described_class.call(node_id: node.id, sensors: nil)
      end

      before do
        stub_request(:post, %r{pushgateway\.example\.com})
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns a success result with empty metrics" do
        expect(result.success?).to be true
      end
    end

    context "when sensors is empty" do
      subject(:result) do
        described_class.call(node_id: node.id, sensors: [])
      end

      before do
        stub_request(:post, %r{pushgateway\.example\.com})
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns a success result with empty metrics" do
        expect(result.success?).to be true
      end
    end

    context "with HTTPS pushgateway URL" do
      let(:pushgateway_url) { "https://pushgateway.example.com:9091" }

      before do
        SshSetting.current.update!(prometheus_pushgateway_url: pushgateway_url)
        stub_request(:post, "https://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
          .to_return(status: 200, body: "", headers: {})
      end

      it "uses SSL for HTTPS URLs" do
        expect(result.success?).to be true
        expect(
          a_request(:post, "https://pushgateway.example.com:9091/metrics/job/qis_bmc_collector/instance/test-node-001")
        ).to have_been_made.once
      end
    end
  end
end
