# frozen_string_literal: true

module Agent
  # Namespace module for all agent lifecycle error classes.
  # Zeitwerk expects this file to define Agent::Errors to match the file path.
  module Errors
    # Base error class for all agent lifecycle operations
    # Provides structured error information including phase, details, and recoverability
    class LifecycleError < StandardError
      attr_reader :phase, :details, :recoverable

      def initialize(message, phase:, details: {}, recoverable: false)
        @phase = phase
        @details = details
        @recoverable = recoverable
        super(message)
      end
    end

    # Raised when SSH connection fails (auth, network, timeout)
    class ConnectionError < LifecycleError; end

    # Raised when pre-flight validation fails
    class ValidationError < LifecycleError; end

    # Raised when file transfer or permission setting fails
    class DeploymentError < LifecycleError; end

    # Raised when systemd service operations fail
    class ServiceError < LifecycleError; end

    # Raised when post-operation health verification fails
    class HealthCheckError < LifecycleError; end

    # Raised when auto-rollback fails
    class RollbackError < LifecycleError; end

    # Raised when attempting to update an agent on a busy node
    class NodeBusyError < LifecycleError
      def initialize(msg = "Update blocked: Node is currently busy (Pending/Running tasks).")
        super(msg, phase: :preflight, recoverable: true)
      end
    end
  end
end
