# frozen_string_literal: true

class EmptyStateComponent < ViewComponent::Base
  renders_one :action

  def initialize(icon:, title:, description: nil, icon_class: "text-neutral-25", testid: nil)
    @icon = icon
    @title = title
    @description = description
    @icon_class = icon_class
    @testid = testid
  end

  private

  attr_reader :icon, :title, :description, :icon_class, :testid
end
