# frozen_string_literal: true

module Mlc
  class ProfileCardComponent < ViewComponent::Base
    def initialize(key:, profile:, selected: false)
      @key = key
      @profile = profile
      @selected = selected
    end

    def card_classes
      base = "relative cursor-pointer rounded-lg border p-4 hover:border-primary-5 transition-colors"
      if selected
        "#{base} border-primary-5 ring-2 ring-primary-5 bg-primary-1"
      else
        "#{base} border-neutral-15 bg-white"
      end
    end

    private

    attr_reader :key, :profile, :selected
  end
end
