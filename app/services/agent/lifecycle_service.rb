# frozen_string_literal: true

require_relative "errors"
require_relative "concerns/remote_execution"

module Agent
  # Base class for all agent lifecycle operations (install, update, uninstall)
  # Provides consistent 5-phase execution: preflight, connect, execute, verify, finalize
  class LifecycleService
    include Concerns::RemoteExecution

    Result = Struct.new(:success, :message, :agent_event, keyword_init: true) do
      def success?
        success
      end
    end

    attr_reader :node, :agent_event

    def initialize(node:, cache_key: nil, user: nil, agent_release: nil, force: false, on_progress: nil)
      @node = node
      @cache_key = cache_key
      @user = user
      @agent_release = agent_release
      @force = force
      @on_progress = on_progress
      @operation_started_at = nil
    end

    def call
      create_agent_event
      @agent_event.mark_running!
      @operation_started_at = Time.current

      resolve_credentials(cache_key: @cache_key) if @cache_key

      run_preflight_checks

      with_connection do |ssh|
        execute_operation(ssh)
        verify_health(ssh)
      end

      finalize
      @agent_event.mark_success!

      Result.new(success: true, message: success_message, agent_event: @agent_event)
    rescue Agent::Errors::LifecycleError => e
      handle_error(e)
      raise
    rescue StandardError => e
      wrapped = Agent::Errors::DeploymentError.new(e.message, phase: :unknown, details: { original_class: e.class.name })
      handle_error(wrapped)
      raise wrapped
    end

    protected

    # Subclasses must implement these methods
    def operation_type
      raise NotImplementedError, "Subclasses must implement #operation_type"
    end

    def execute_operation(_ssh)
      raise NotImplementedError, "Subclasses must implement #execute_operation"
    end

    def run_preflight_checks
      raise Errors::ValidationError.new("Node must be persisted", phase: :preflight) unless @node.persisted?
    end

    def verify_health(_ssh)
      # Default: no verification. Subclasses can override.
    end

    def finalize
      # Default: no finalization. Subclasses can override.
    end

    def success_message
      "Operation completed successfully"
    end

    def expected_version
      @agent_release&.version || "dev"
    end

    private

    def create_agent_event
      @agent_event = AgentEvent.create!(
        node: @node,
        user: @user,
        agent_release: @agent_release,
        operation: operation_type,
        status: :pending,
        from_version: @node.agent_version,
        to_version: expected_version,
        forced: @force
      )
    end

    def with_connection(&block)
      if localhost_target?
        report_progress "Executing locally (localhost detected)"
        yield nil
      elsif use_bastion?
        connect_via_bastion(&block)
      else
        connect_direct(&block)
      end
    end

    def connect_direct(&block)
      primary_host = @node.ip.presence || @node.hostname
      fallback_host = determine_fallback_host(primary_host)

      begin
        attempt_connection(primary_host, &block)
      rescue Errors::ConnectionError => e
        raise unless fallback_host && e.recoverable

        report_progress "Connection to #{primary_host} failed, retrying with #{fallback_host}..."
        attempt_connection(fallback_host, &block)
      end
    end

    def attempt_connection(host, &block)
      report_progress "Connecting directly to #{host}"
      Net::SSH.start(host, ssh_user, ssh_options.merge(port: @node.ssh_port || 22), &block)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
           Net::SSH::ConnectionTimeout => e
      raise Errors::ConnectionError.new(
        "SSH connection failed: #{e.message}",
        phase: :connect,
        details: { host: host, error_class: e.class.name },
        recoverable: true
      )
    rescue Net::SSH::AuthenticationFailed => e
      raise Errors::ConnectionError.new(
        "SSH authentication failed: #{e.message}",
        phase: :connect,
        details: { host: host, error_class: e.class.name },
        recoverable: false
      )
    end

    def determine_fallback_host(primary_host)
      return nil if @node.ip.blank?
      return nil if @node.hostname.blank?
      return nil if @node.hostname == @node.ip
      return nil if primary_host == @node.hostname

      @node.hostname
    end

    def connect_via_bastion(&block)
      gateway_host = @node.jump_host.presence || ::SshConfig.jump_host
      gateway_user = @node.jump_user.presence || ::SshConfig.jump_user || ssh_user
      gateway_port = @node.jump_port || ::SshConfig.jump_port || 22

      report_progress "Connecting via bastion #{gateway_host}"

      Net::SSH.start(gateway_host, gateway_user, ssh_options.merge(port: gateway_port), &block)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Net::SSH::AuthenticationFailed => e
      raise Errors::ConnectionError.new(
        "Bastion connection failed: #{e.message}",
        phase: :connect,
        details: { bastion: gateway_host, error_class: e.class.name },
        recoverable: true
      )
    end

    def handle_error(error)
      details = error.details.merge(phase: error.phase)

      @agent_event&.mark_failed!(
        message: error.message,
        details: details
      )

      Rails.logger.error "[#{self.class.name}] #{error.class.name}: #{error.message}"
      Rails.logger.error "[#{self.class.name}] Phase: #{error.phase}, Details: #{error.details.inspect}"
    end
  end
end
