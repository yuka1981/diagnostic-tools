# frozen_string_literal: true

class FormFieldComponent < ViewComponent::Base
  renders_one :input

  BASE_INPUT_CLASSES = "block w-full rounded-md shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm"
  NORMAL_BORDER = "border-neutral-15"
  ERROR_BORDER = "border-error-3 focus:border-error-5 focus:ring-error-5"

  def initialize(form:, attribute:, label:, hint: nil, placeholder: nil, required: false)
    @form = form
    @attribute = attribute
    @label = label
    @hint = hint
    @placeholder = placeholder
    @required = required
  end

  def input_classes
    border_class = errors? ? ERROR_BORDER : NORMAL_BORDER
    "#{BASE_INPUT_CLASSES} #{border_class}"
  end

  def errors?
    form.object&.errors&.[](attribute)&.any?
  end

  def error_messages
    form.object&.errors&.[](attribute) || []
  end

  private

  attr_reader :form, :attribute, :label, :hint, :placeholder, :required
end
