# frozen_string_literal: true

module Mlc
  class ProfileSelectorComponent < ViewComponent::Base
    def initialize(selected: "quick")
      @selected = selected.to_sym
    end

    def profiles
      Mlc::PROFILES
    end

    def selected?(key)
      key == @selected
    end

    private

    attr_reader :selected
  end
end
