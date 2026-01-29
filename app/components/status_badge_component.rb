# frozen_string_literal: true

class StatusBadgeComponent < ViewComponent::Base
  # Reuse color mappings from DashboardHelper to avoid duplication
  STATUS_COLORS = DashboardHelper::COLOR_MAPS
  STATUS_MAPPING = DashboardHelper::STATUS_COLORS

  SIZE_CLASSES = {
    default: "px-2 py-0.5 text-xs",
    small: "px-1.5 py-0.5 text-[9px]"
  }.freeze

  def initialize(status:, label: nil, size: :default, testid: nil)
    @status = status
    @label = label
    @size = size
    @testid = testid
  end

  def color_classes
    variant = STATUS_MAPPING[status.to_s] || status.to_sym
    color_map = STATUS_COLORS[variant] || STATUS_COLORS[:muted]
    color_map[:badge]
  end

  def size_classes
    SIZE_CLASSES.fetch(size, SIZE_CLASSES[:default])
  end

  def display_label
    label || status.to_s.titleize
  end

  def testid_attribute
    return nil unless testid
    "#{testid}-#{status}"
  end

  private

  attr_reader :status, :label, :size, :testid
end
