# frozen_string_literal: true

class InventoryCollectJob < ApplicationJob
  queue_as :default

  # Retry only on transient network errors (connection timeout)
  # Other SSH errors (AuthenticationFailed, HostKeyMismatch) are non-retriable
  retry_on Net::SSH::ConnectionTimeout, wait: :polynomially_longer, attempts: 3

  # Discard job if node no longer exists
  discard_on ActiveRecord::RecordNotFound

  # @param target_node_id [Integer] The ID of the node to collect data from
  # @param gateway_node_id [Integer, nil] Optional ID of the gateway node
  # @param user_id [Integer, nil] Optional ID of the user who triggered the collection
  # @param options [Hash] Additional options (ssh_config, agent_path)
  def perform(target_node_id, gateway_node_id: nil, user_id: nil, **options)
    target_node = Node.find(target_node_id)
    gateway_node = gateway_node_id ? Node.find(gateway_node_id) : nil
    notification = nil

    # Create notification if user_id is provided
    if user_id.present?
      user = User.find_by(id: user_id)
      if user
        notification = NotificationService.create(
          user: user,
          type: "inventory_collect",
          title: "Collecting inventory from #{target_node.hostname}",
          resource: target_node
        )
        NotificationService.start(notification)
      end
    end

    result = Inventory::TriggerCollectService.new(
      target_node,
      gateway: gateway_node,
      **options
    ).call

    if result.success?
      process_collected_data(target_node, result.output)
      NotificationService.complete(notification, success: true, message: "Inventory collected successfully") if notification
    else
      handle_collection_error(target_node, result.error)
      NotificationService.complete(notification, success: false, message: result.error) if notification
    end
  rescue Net::SSH::AuthenticationFailed => e
    # Non-retriable: Authentication failure should not be retried
    handle_ssh_error(target_node, "Authentication failed: #{e.message}")
    NotificationService.complete(notification, success: false, message: "Authentication failed: #{e.message}") if notification
  rescue Net::SSH::HostKeyMismatch => e
    # Non-retriable: Host key issues require manual intervention
    handle_ssh_error(target_node, "Host key verification failed: #{e.message}")
    NotificationService.complete(notification, success: false, message: "Host key verification failed") if notification
  rescue Net::SSH::Exception => e
    # Catch-all for other SSH errors (non-retriable by default)
    handle_ssh_error(target_node, "SSH error: #{e.message}")
    NotificationService.complete(notification, success: false, message: e.message) if notification
  end

  private

  def process_collected_data(node, raw_json)
    if raw_json.is_a?(Hash) && raw_json[:async]
      Rails.logger.info("[InventoryCollectJob] Command broadcasted via WebSocket for #{node.hostname}. Waiting for callback.")
      return
    end

    # Use ProcessStateService to handle versioning
    Inventory::ProcessStateService.new(
      node_id: node.id,
      raw_json: raw_json
    ).call
  end

  def handle_collection_error(node, error_message)
    Rails.logger.error("[InventoryCollectJob] Failed to collect data from #{node.hostname}: #{error_message}")
  end

  def handle_ssh_error(node, error_message)
    Rails.logger.error("[InventoryCollectJob] SSH error for #{node.hostname}: #{error_message}")
    # Non-retriable SSH errors are logged but not re-raised
    # This allows the job to complete without retry
  end
end
