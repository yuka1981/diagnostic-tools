# frozen_string_literal: true

class NodeFormComponent < ViewComponent::Base
  def initialize(node:)
    @node = node
  end
end
