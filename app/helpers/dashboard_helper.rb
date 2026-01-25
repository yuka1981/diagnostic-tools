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
      badge: "bg-blue-100 text-blue-800 border border-blue-200",
      bg: "bg-blue-100",
      text: "text-blue-800"
    },
    warning: {
      badge: "bg-yellow-100 text-yellow-800 border border-yellow-200",
      bg: "bg-yellow-100",
      text: "text-yellow-800"
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
    "compute" => "bg-blue-100 text-blue-700 border border-blue-200",
    "login" => "bg-purple-100 text-purple-700 border border-purple-200",
    "admin" => "bg-amber-100 text-amber-700 border border-amber-200"
  }.freeze

  DEFAULT_BADGE_CLASS = COLOR_MAPS[:muted][:badge]
  DEFAULT_BG_CLASS = COLOR_MAPS[:muted][:bg]
  DEFAULT_TEXT_COLOR = COLOR_MAPS[:muted][:text]

  # Heatmap cell colors based on node role and status
  HEATMAP_COLORS = {
    compute: {
      online: "bg-emerald-500 hover:bg-emerald-400",
      offline: "bg-neutral-15 hover:bg-neutral-8"
    },
    login: {
      online: "bg-blue-500 hover:bg-blue-400",
      offline: "bg-neutral-15 hover:bg-neutral-8"
    },
    admin: {
      online: "bg-amber-500 hover:bg-amber-400",
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
    content_tag(:svg, class: "h-5 w-5 text-emerald-600 dark:text-emerald-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end

  def failed_icon
    content_tag(:svg, class: "h-5 w-5 text-error-6 dark:text-error-4", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end

  def running_icon
    content_tag(:svg, class: "h-5 w-5 text-blue-600 dark:text-blue-400 animate-spin", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15")
    end
  end

  def pending_icon
    content_tag(:svg, class: "h-5 w-5 text-amber-600 dark:text-amber-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end

  def cancelled_icon
    content_tag(:svg, class: "h-5 w-5 text-gray-600 dark:text-gray-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636")
    end
  end

  def unknown_icon
    content_tag(:svg, class: "h-5 w-5 text-gray-600 dark:text-gray-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end
end
