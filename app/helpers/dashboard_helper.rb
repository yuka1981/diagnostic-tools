# frozen_string_literal: true

module DashboardHelper
  COLOR_MAPS = {
    success: {
      badge: "bg-success-2 text-success-7 border border-success-2",
      bg: "bg-success-2",
      text: "text-success-7"
    },
    error: {
      badge: "bg-error-1 text-error-7 border border-error-2",
      bg: "bg-error-1",
      text: "text-error-7"
    },
    running: {
      badge: "bg-primary-1 text-primary-7 border border-primary-2",
      bg: "bg-primary-1",
      text: "text-primary-7"
    },
    warning: {
      badge: "bg-warning-1 text-warning-7 border border-warning-2",
      bg: "bg-warning-1",
      text: "text-warning-7"
    },
    muted: {
      badge: "bg-neutral-4 text-neutral-85 border border-neutral-8",
      bg: "bg-neutral-4",
      text: "text-neutral-45"
    }
  }.freeze

  STATUS_COLORS = {
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

  ROLE_BADGE_CLASSES = {
    "compute" => "bg-primary-1 text-primary-7 border border-primary-2",
    "login" => "bg-login-1 text-login-7 border border-login-2",
    "admin" => "bg-warning-1 text-warning-7 border border-warning-2"
  }.freeze

  DEFAULT_BADGE_CLASS = COLOR_MAPS[:muted][:badge]
  DEFAULT_BG_CLASS = COLOR_MAPS[:muted][:bg]
  DEFAULT_TEXT_COLOR = COLOR_MAPS[:muted][:text]

  # Heatmap cell colors based on node role and status
  HEATMAP_COLORS = {
    compute: {
      online: "bg-success-5 hover:bg-success-4",
      offline: "bg-neutral-15 hover:bg-neutral-8"
    },
    login: {
      online: "bg-login-5 hover:bg-login-4",
      offline: "bg-neutral-15 hover:bg-neutral-8"
    },
    admin: {
      online: "bg-warning-5 hover:bg-warning-4",
      offline: "bg-neutral-15 hover:bg-neutral-8"
    }
  }.freeze

  def node_heatmap_class(node)
    role = node.role.to_sym
    status = node.online? ? :online : :offline

    HEATMAP_COLORS.dig(role, status)
  end

  def status_badge_class(status)
    color_key = STATUS_COLORS[status.to_s]
    return DEFAULT_BADGE_CLASS unless color_key

    COLOR_MAPS[color_key][:badge]
  end

  def status_bg_class(status)
    color_key = STATUS_COLORS[status.to_s]
    return DEFAULT_BG_CLASS unless color_key

    COLOR_MAPS[color_key][:bg]
  end

  def status_text_color(status)
    color_key = STATUS_COLORS[status.to_s]
    return DEFAULT_TEXT_COLOR unless color_key

    COLOR_MAPS[color_key][:text]
  end

  def role_badge_class(role)
    ROLE_BADGE_CLASSES.fetch(role.to_s, DEFAULT_BADGE_CLASS)
  end

  def status_icon(status)
    case status.to_s
    when "success"
      success_icon
    when "failed"
      failed_icon
    when "running"
      running_icon
    when "pending"
      pending_icon
    when "cancelled"
      cancelled_icon
    else
      unknown_icon
    end
  end

  private

  def success_icon
    content_tag(:svg, class: "h-5 w-5 text-success-6", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end

  def failed_icon
    content_tag(:svg, class: "h-5 w-5 text-error-6", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end

  def running_icon
    content_tag(:svg, class: "h-5 w-5 text-primary-6 animate-spin", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15")
    end
  end

  def pending_icon
    content_tag(:svg, class: "h-5 w-5 text-pending-6", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end

  def cancelled_icon
    content_tag(:svg, class: "h-5 w-5 text-neutral-45", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636")
    end
  end

  def unknown_icon
    content_tag(:svg, class: "h-5 w-5 text-neutral-45", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end
end
