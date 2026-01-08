# frozen_string_literal: true

require "digest"
require "json"

class NodeState < ApplicationRecord
  # Associations
  belongs_to :node

  # Validations
  validates :captured_at, presence: true

  # Scopes
  scope :latest_first, -> { order(captured_at: :desc) }
  scope :for_node, ->(node) { where(node: node) }

  # Generate a hash of the content for comparison (memoized for performance)
  # Uses sorted keys to ensure consistent hashing regardless of key order
  def content_hash
    @content_hash ||= begin
      content = {
        host_info: deep_sort_keys(host_info),
        cpu_info: deep_sort_keys(cpu_info),
        mem_info: deep_sort_keys(mem_info),
        disk_info: deep_sort_keys(disk_info),
        net_info: deep_sort_keys(net_info),
        dmi_info: deep_sort_keys(dmi_info)
      }

      Digest::SHA256.hexdigest(JSON.generate(content))
    end
  end

  # Compare content with another state (type-safe)
  def same_content_as?(other)
    other.is_a?(NodeState) && content_hash == other.content_hash
  end

  private

  # Recursively sort hash keys to ensure consistent JSON output
  def deep_sort_keys(obj)
    case obj
    when Hash
      obj.sort.to_h.transform_values { |v| deep_sort_keys(v) }
    when Array
      obj.map { |item| deep_sort_keys(item) }
    else
      obj
    end
  end
end
