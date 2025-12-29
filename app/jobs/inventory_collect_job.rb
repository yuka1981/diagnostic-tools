# frozen_string_literal: true

class InventoryCollectJob < ApplicationJob
  queue_as :default

  # Retry on network errors
  retry_on Net::SSH::ConnectionTimeout, wait: :polynomially_longer, attempts: 3
  retry_on Net::SSH::Exception, wait: 5.seconds, attempts: 2

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
  end

  private

  def process_collected_data(node, raw_json)
    # Use ProcessStateService to handle versioning
    Inventory::ProcessStateService.new(
      node_id: node.id,
      raw_json: raw_json
    ).call
  end

  def handle_collection_error(node, error_message)
    Rails.logger.error("[InventoryCollectJob] Failed to collect data from #{node.hostname}: #{error_message}")

    # Optionally: Update node status or create an alert
    # This could be extended to notify admins or update a status field
  end
end
