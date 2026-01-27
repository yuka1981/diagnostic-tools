# frozen_string_literal: true

module Bmc
  class CollectInventoryJob < ApplicationJob
    queue_as :default

    # Retry only on transient network errors (connection timeout)
    # Other SSH errors (AuthenticationFailed, HostKeyMismatch) are non-retriable
    retry_on Net::SSH::ConnectionTimeout, wait: :polynomially_longer, attempts: 3

    # Discard job if node no longer exists
    discard_on ActiveRecord::RecordNotFound

    # @param node_id [Integer] The ID of the node to collect BMC inventory for
    # @param user_id [Integer, nil] Optional ID of the user who triggered the collection
    def perform(node_id, user_id: nil)
      node = Node.find(node_id)
      notification = nil

      # Create notification if user_id is provided
      if user_id.present?
        user = User.find_by(id: user_id)
        if user
          notification = NotificationService.create(
            user: user,
            type: "bmc_inventory_collect",
            title: "Collecting BMC inventory from #{node.hostname}",
            resource: node
          )
          NotificationService.start(notification)
        end
      end

      # Get SSH settings for bastion/admin node connection
      ssh_settings = SshSetting.current

      # Build and execute the collector command
      command = build_collector_command(node)
      result = execute_ssh_command(ssh_settings, command)

      if result[:success]
        Rails.logger.info "[Bmc::CollectInventoryJob] BMC collection completed for node #{node.hostname}"
        NotificationService.complete(notification, success: true, message: "BMC inventory collected successfully") if notification
      else
        Rails.logger.error "[Bmc::CollectInventoryJob] BMC collection failed for node #{node.hostname}: #{result[:error]}"
        NotificationService.complete(notification, success: false, message: result[:error]) if notification
      end
    rescue Net::SSH::AuthenticationFailed => e
      handle_ssh_error(node, "Authentication failed: #{e.message}", notification)
    rescue Net::SSH::HostKeyMismatch => e
      handle_ssh_error(node, "Host key verification failed: #{e.message}", notification)
    rescue Net::SSH::Exception => e
      handle_ssh_error(node, "SSH error: #{e.message}", notification)
    end

    private

    def build_collector_command(node)
      # qis-bmc-collector is the external tool that runs on the bastion/admin node
      # It collects BMC inventory data via Redfish/IPMI and pushes it back to this server
      "qis-bmc-collector inventory --node #{Shellwords.escape(node.hostname)}"
    end

    def execute_ssh_command(settings, command)
      require "net/ssh"

      bastion_host = settings.bastion_host
      bastion_user = settings.bastion_user || settings.ssh_user
      bastion_port = settings.bastion_port || 22

      return { success: false, error: "Bastion host not configured" } if bastion_host.blank?

      ssh_options = build_ssh_options(settings)

      begin
        output = ""
        Net::SSH.start(bastion_host, bastion_user, ssh_options.merge(port: bastion_port)) do |ssh|
          output = ssh.exec!(command)
        end
        { success: true, output: output }
      rescue Net::SSH::Exception
        # Re-raise SSH exceptions to be handled by perform method
        raise
      rescue StandardError => e
        { success: false, error: e.message }
      end
    end

    def build_ssh_options(settings)
      options = {
        timeout: settings.timeout || 30,
        non_interactive: true
      }

      # Add key data if available
      if settings.ssh_key.present?
        options[:key_data] = [ settings.ssh_key ]
      end

      # Add password if available
      if settings.ssh_password.present?
        options[:password] = settings.ssh_password
      end

      # Host key verification
      options[:verify_host_key] = settings.verify_host_key ? :always : :never

      options
    end

    def handle_ssh_error(node, error_message, notification)
      Rails.logger.error "[Bmc::CollectInventoryJob] SSH error for #{node.hostname}: #{error_message}"
      NotificationService.complete(notification, success: false, message: error_message) if notification
      # Non-retriable SSH errors are logged but not re-raised
      # This allows the job to complete without retry
    end
  end
end
