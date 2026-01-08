# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::TriggerCollectService, type: :service do
  let(:node) { create(:node, hostname: "test-node") }
  let(:service) { described_class.new(node) }

  describe "#process_result" do
    it "successfully parses JSON from stdout even if stderr has warnings" do
      json_output = { host: { hostname: "test-node" } }.to_json
      warning_output = "2026/01/08 12:10:41 Warning: failed to collect DMI information: exit status 1"
      
      result = SshExecutionService::Result.new(
        success: true, 
        output: json_output, 
        error: warning_output
      )

      processed = service.send(:process_result, result)
      
      expect(processed.success?).to be true
      expect(processed.output[:host][:hostname]).to eq("test-node")
    end

    it "reports an error if JSON parsing fails" do
      result = SshExecutionService::Result.new(
        success: true, 
        output: "Not a JSON", 
        error: "Some error"
      )

      processed = service.send(:process_result, result)
      
      expect(processed.success?).to be false
      expect(processed.error).to include("JSON parse error")
      expect(processed.error).to include("Some error")
      expect(processed.error).to include("Not a JSON")
    end
  end
end