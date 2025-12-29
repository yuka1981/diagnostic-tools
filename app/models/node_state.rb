# frozen_string_literal: true

require "digest"

class NodeState < ApplicationRecord
  # Associations
  belongs_to :node

  # Validations
  validates :captured_at, presence: true

  # Scopes
  scope :latest_first, -> { order(captured_at: :desc) }
  scope :for_node, ->(node) { where(node: node) }

  # Generate a hash of the content for comparison
  def content_hash
    content = {
      cpu_info: cpu_info,
      mem_info: mem_info,
      disk_info: disk_info,
      net_info: net_info
    }
    Digest::SHA256.hexdigest(content.to_json)
  end

  # Compare content with another state
  def same_content_as?(other)
    return false if other.nil?

    content_hash == other.content_hash
  end
end
