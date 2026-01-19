# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/agent/errors"

RSpec.describe Agent::Errors::LifecycleError do
  describe "initialization" do
    it "accepts message, phase, details, and recoverable" do
      error = described_class.new("Something failed", phase: :preflight, details: { foo: "bar" }, recoverable: true)
      expect(error.message).to eq("Something failed")
      expect(error.phase).to eq(:preflight)
      expect(error.details).to eq({ foo: "bar" })
      expect(error.recoverable).to be true
    end

    it "defaults details to empty hash and recoverable to false" do
      error = described_class.new("Failed", phase: :deploy)
      expect(error.details).to eq({})
      expect(error.recoverable).to be false
    end
  end

  it "is a StandardError" do
    expect(described_class.new("test", phase: :test)).to be_a(StandardError)
  end
end

RSpec.describe Agent::Errors::ConnectionError do
  it "inherits from LifecycleError" do
    expect(described_class.new("SSH failed", phase: :connect)).to be_a(Agent::Errors::LifecycleError)
  end
end

RSpec.describe Agent::Errors::ValidationError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Invalid", phase: :preflight)).to be_a(Agent::Errors::LifecycleError)
  end
end

RSpec.describe Agent::Errors::DeploymentError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Deploy failed", phase: :deploy)).to be_a(Agent::Errors::LifecycleError)
  end
end

RSpec.describe Agent::Errors::ServiceError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Service failed", phase: :start)).to be_a(Agent::Errors::LifecycleError)
  end
end

RSpec.describe Agent::Errors::HealthCheckError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Health check failed", phase: :verify)).to be_a(Agent::Errors::LifecycleError)
  end
end

RSpec.describe Agent::Errors::RollbackError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Rollback failed", phase: :rollback)).to be_a(Agent::Errors::LifecycleError)
  end
end
