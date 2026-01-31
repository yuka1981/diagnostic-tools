# frozen_string_literal: true

module Bmc
  class ReconciliationService
    def initialize(node)
      @node = node
    end

    def call
      { compared: false, reason: "not yet implemented" }
    end
  end
end
