# frozen_string_literal: true

class SlideOverComponent < ViewComponent::Base
  renders_one :header_badge
  renders_many :tabs, ->(name:, active: false, &block) {
    SlideOverTabComponent.new(name: name, active: active, content: block)
  }

  def initialize(title:)
    @title = title
  end

  private

  attr_reader :title

  class SlideOverTabComponent < ViewComponent::Base
    attr_reader :name, :active, :content

    def initialize(name:, active:, content:)
      @name = name
      @active = active
      @content = content
    end

    def tab_id
      "tab-#{name.parameterize}"
    end

    def panel_id
      "tab-panel-#{name.parameterize}"
    end

    def active_tab_classes
      if active
        "border-b-2 border-primary-6 px-4 py-3 text-sm font-bold uppercase text-primary-6 focus:outline-none transition-colors"
      else
        "border-b-2 border-transparent px-4 py-3 text-sm font-bold uppercase text-neutral-45 hover:text-neutral-85 hover:border-neutral-15 focus:outline-none transition-colors"
      end
    end

    def panel_classes
      active ? "" : "hidden"
    end

    def call
      content.call
    end
  end
end
