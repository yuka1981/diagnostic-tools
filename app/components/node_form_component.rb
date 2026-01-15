# frozen_string_literal: true

class NodeFormComponent < ViewComponent::Base
  def initialize(node:, api_keys: [])
    @node = node
    @api_keys = api_keys
  end
end
