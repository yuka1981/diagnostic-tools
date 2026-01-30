# frozen_string_literal: true

class AgentEvent < ApplicationRecord
  belongs_to :node
end
