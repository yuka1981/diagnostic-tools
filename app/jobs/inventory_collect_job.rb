# frozen_string_literal: true

class InventoryCollectJob < ApplicationJob
  queue_as :default

  # Retry on transient Salt API timeouts
  retry_on SaltApiClient::TimeoutError, wait: :polynomially_longer, attempts: 3

  # Discard job if node no longer exists
  discard_on ActiveRecord::RecordNotFound

  # @param target_node_id [Integer] The ID of the node to collect data from
  # @param user_id [Integer, nil] Optional ID of the user who triggered the collection
  def perform(target_node_id, user_id: nil)
    target_node = Node.find(target_node_id)
    notification = create_notification(target_node, user_id)

    result = Inventory::SaltCollectService.new(target_node).call

    if result.success?
      complete_notification(notification, :success, "Inventory collected successfully")
    else
      Rails.logger.error("[InventoryCollectJob] Failed to collect from #{target_node.hostname}: #{result.error}")
      complete_notification(notification, :failure, result.error)
    end
  end

  private

  def create_notification(node, user_id)
    return nil unless user_id.present?

    user = User.find_by(id: user_id)
    return nil unless user

    notification = NotificationService.create(
      user: user,
      type: "inventory_collect",
      title: "Collecting inventory from #{node.hostname}",
      resource: node
    )
    NotificationService.start(notification)
    notification
  rescue StandardError
    nil
  end

  def complete_notification(notification, status, message)
    return unless notification

    NotificationService.complete(notification, success: status == :success, message: message)
  rescue StandardError
    nil
  end
end
