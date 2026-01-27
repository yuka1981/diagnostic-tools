# frozen_string_literal: true

class CardComponent < ViewComponent::Base
  renders_one :action

  def initialize(title: nil, padding: true, **options)
    @title = title
    @padding = padding
    @options = options
  end

  def card_classes
    classes = [ "card-netbox" ]
    classes << options[:class] if options[:class]
    classes.join(" ")
  end

  def body_classes
    padding ? "p-4" : nil
  end

  def header?
    title.present?
  end

  private

  attr_reader :title, :padding, :options
end
