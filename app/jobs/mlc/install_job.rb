module Mlc
  class InstallJob < ApplicationJob
    queue_as :default

    def perform(installation_id, server_url, user_id: nil)
      @installation = MlcInstallation.find(installation_id)
      @server_url = server_url
      @user_id = user_id

      @installation.update!(status: :running, started_at: Time.current)
      broadcast_status_update

      process_nodes
    rescue StandardError => e
      @installation&.update!(status: :failed, completed_at: Time.current)
      notify_failure(e.message)
      raise
    end

    private

    def process_nodes
      pending_nodes = @installation.mlc_installation_nodes.pending.includes(:node)

      pending_nodes.find_each do |installation_node|
        result = process_single_node(installation_node)

        if !result.success? && @installation.stop_on_first?
          skip_remaining_nodes(pending_nodes.where("id > ?", installation_node.id))
          @installation.update!(status: :failed, completed_at: Time.current)
          notify_failure("Installation stopped: #{result.error}")
          return
        end
      end

      finalize_installation
    end

    def process_single_node(installation_node)
      installation_node.update!(status: :running, started_at: Time.current, step_current: 1, step_name: "Starting")
      broadcast_node_update(installation_node)

      # TODO: Replace with Salt-based MLC installation service
      raise NotImplementedError, "MLC installation via Salt not yet implemented"
    end

    def skip_remaining_nodes(nodes)
      nodes.update_all(status: :skipped, completed_at: Time.current)
    end

    def finalize_installation
      if @installation.mlc_installation_nodes.failed.any?
        @installation.update!(status: :failed, completed_at: Time.current)
      else
        @installation.update!(status: :completed, completed_at: Time.current)
      end

      notify_completion
    end

    def broadcast_status_update
      return unless defined?(Turbo::StreamsChannel)

      @installation.broadcast_replace_to(
        "mlc_installation_#{@installation.id}",
        target: "mlc_installation_status",
        partial: "mlc_installations/status",
        locals: { installation: @installation }
      )
    rescue StandardError
      # Ignore broadcast errors
    end

    def broadcast_node_update(installation_node)
      return unless defined?(Turbo::StreamsChannel)

      installation_node.broadcast_replace_to(
        "mlc_installation_#{@installation.id}",
        target: "mlc_installation_node_#{installation_node.id}",
        partial: "mlc_installations/node_status",
        locals: { installation_node: installation_node }
      )
    rescue StandardError
      # Ignore broadcast errors
    end

    def notify_completion
      return unless @user_id && defined?(NotificationService)

      NotificationService.new.notify(
        user_id: @user_id,
        title: "MLC Installation #{@installation.completed? ? 'Complete' : 'Failed'}",
        message: "Installation #{@installation.uuid} finished with status: #{@installation.status}"
      )
    rescue StandardError
      # Ignore notification errors
    end

    def notify_failure(message)
      return unless @user_id && defined?(NotificationService)

      NotificationService.new.notify(
        user_id: @user_id,
        title: "MLC Installation Failed",
        message: message
      )
    rescue StandardError
      # Ignore notification errors
    end
  end
end
