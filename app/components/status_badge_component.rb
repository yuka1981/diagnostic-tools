# frozen_string_literal: true

class StatusBadgeComponent < ViewComponent::Base
  STATUS_COLORS = {
    success: "bg-success-2 text-success-7 border border-success-2",
    error: "bg-error-1 text-error-7 border border-error-2",
    running: "bg-primary-1 text-primary-7 border border-primary-2",
    warning: "bg-warning-1 text-warning-7 border border-warning-2",
    muted: "bg-neutral-4 text-neutral-85 border border-neutral-8"
  }.freeze

  STATUS_MAPPING = {
    "success" => :success,
    "completed" => :success,
    "passed" => :success,
    "online" => :success,
    "failed" => :error,
    "offline" => :error,
    "error" => :error,
    "running" => :running,
    "pending" => :warning,
    "warning" => :warning,
    "unknown" => :warning,
    "cancelled" => :muted
  }.freeze

  SIZE_CLASSES = {
    default: "px-2 py-0.5 text-xs",
    small: "px-1.5 py-0.5 text-[9px]"
  }.freeze

  def initialize(status:, label: nil, size: :default)
    @status = status
    @label = label
    @size = size
  end

  def color_classes
    variant = STATUS_MAPPING[status.to_s] || status.to_sym
    STATUS_COLORS.fetch(variant, STATUS_COLORS[:muted])
  end

  def size_classes
    SIZE_CLASSES.fetch(size, SIZE_CLASSES[:default])
  end

  def display_label
    label || status.to_s.titleize
  end

  private

  attr_reader :status, :label, :size
end
