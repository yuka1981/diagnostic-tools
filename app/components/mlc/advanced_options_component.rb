# frozen_string_literal: true

module Mlc
  class AdvancedOptionsComponent < ViewComponent::Base
    def initialize(form:)
      @form = form
    end

    private

    attr_reader :form
  end
end
