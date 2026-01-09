# frozen_string_literal: true

class NodeFormComponent < ViewComponent::Base
  def initialize(node:, show_actions: true)
    @node = node
    @show_actions = show_actions
  end
end
