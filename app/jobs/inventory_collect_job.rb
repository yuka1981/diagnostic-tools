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
  # @param options [Hash] Additional options (ssh_config, agent_path)
  def perform(target_node_id, gateway_node_id: nil, **options)
    target_node = Node.find(target_node_id)
    gateway_node = gateway_node_id ? Node.find(gateway_node_id) : nil

    result = Inventory::TriggerCollectService.new(
      target_node,
      gateway: gateway_node,
      **options
    ).call

    if result.success?
      process_collected_data(target_node, result.output)
    else
      handle_collection_error(target_node, result.error)
    end
  rescue Net::SSH::AuthenticationFailed => e
    # Non-retriable: Authentication failure should not be retried
    handle_ssh_error(target_node, "Authentication failed: #{e.message}")
  rescue Net::SSH::HostKeyMismatch => e
    # Non-retriable: Host key issues require manual intervention
    handle_ssh_error(target_node, "Host key verification failed: #{e.message}")
  rescue Net::SSH::Exception => e
    # Catch-all for other SSH errors (non-retriable by default)
    handle_ssh_error(target_node, "SSH error: #{e.message}")
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
