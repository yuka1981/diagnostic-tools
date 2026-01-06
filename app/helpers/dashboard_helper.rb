# frozen_string_literal: true

module DashboardHelper
  STATUS_BADGE_CLASSES = {
    "success" => "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-400",
    "failed" => "bg-red-100 text-red-700 dark:bg-red-500/20 dark:text-red-400",
    "running" => "bg-blue-100 text-blue-700 dark:bg-blue-500/20 dark:text-blue-400",
    "building" => "bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-400",
    "preparing" => "bg-indigo-100 text-indigo-700 dark:bg-indigo-500/20 dark:text-indigo-300",
    "uploading" => "bg-purple-100 text-purple-700 dark:bg-purple-500/20 dark:text-purple-300",
    "pending" => "bg-slate-100 text-slate-700 dark:bg-slate-500/20 dark:text-slate-200",
    "lost" => "bg-gray-100 text-gray-700 dark:bg-gray-500/20 dark:text-gray-400"
  }.freeze

  STATUS_BG_CLASSES = {
    "success" => "bg-emerald-100 dark:bg-emerald-500/20",
    "failed" => "bg-red-100 dark:bg-red-500/20",
    "running" => "bg-blue-100 dark:bg-blue-500/20",
    "building" => "bg-amber-100 dark:bg-amber-500/20",
    "preparing" => "bg-indigo-100 dark:bg-indigo-500/20",
    "uploading" => "bg-purple-100 dark:bg-purple-500/20",
    "pending" => "bg-slate-100 dark:bg-slate-500/20",
    "lost" => "bg-gray-100 dark:bg-gray-500/20"
  }.freeze

  ROLE_BADGE_CLASSES = {
    "compute" => "bg-blue-100 text-blue-700 dark:bg-blue-500/20 dark:text-blue-400",
    "login" => "bg-purple-100 text-purple-700 dark:bg-purple-500/20 dark:text-purple-400",
    "admin" => "bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-400"
  }.freeze

  DEFAULT_BADGE_CLASS = "bg-gray-100 text-gray-700 dark:bg-gray-500/20 dark:text-gray-400"
  DEFAULT_BG_CLASS = "bg-gray-100 dark:bg-gray-500/20"

  # Heatmap cell colors based on node role and status
  HEATMAP_COLORS = {
    compute: {
      online: "bg-emerald-500 hover:bg-emerald-400 dark:bg-emerald-600 dark:hover:bg-emerald-500",
      offline: "bg-gray-300 hover:bg-gray-200 dark:bg-slate-600 dark:hover:bg-slate-500"
    },
    login: {
      online: "bg-blue-500 hover:bg-blue-400 dark:bg-blue-600 dark:hover:bg-blue-500",
      offline: "bg-gray-300 hover:bg-gray-200 dark:bg-slate-600 dark:hover:bg-slate-500"
    },
    admin: {
      online: "bg-amber-500 hover:bg-amber-400 dark:bg-amber-600 dark:hover:bg-amber-500",
      offline: "bg-gray-300 hover:bg-gray-200 dark:bg-slate-600 dark:hover:bg-slate-500"
    }
  }.freeze

  def node_heatmap_class(node)
    role = node.role.to_sym
    status = node.online? ? :online : :offline

    HEATMAP_COLORS.dig(role, status)
  end

  def status_badge_class(status)
    STATUS_BADGE_CLASSES.fetch(status.to_s, DEFAULT_BADGE_CLASS)
  end

  def status_bg_class(status)
    STATUS_BG_CLASSES.fetch(status.to_s, DEFAULT_BG_CLASS)
  end

  def status_label(status)
    case status.to_s
    when "building" then "Building..."
    when "running" then "Running..."
    when "preparing" then "Preparing..."
    when "uploading" then "Uploading..."
    when "lost" then "Lost Connection"
    else
      status.to_s.humanize
    end
  end

  def benchmark_status_badge(status, size: :default)
    badge_size_classes = size == :small ? "px-2 py-0.5 text-[10px]" : "px-2.5 py-0.5 text-xs"

    content_tag(:span, class: "inline-flex items-center gap-1 rounded-full font-medium #{badge_size_classes} #{status_badge_class(status)}") do
      safe_join([ status_spinner(status), status_label(status) ].compact, " ")
    end
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
    when "lost"
      lost_icon
    when "building"
      pending_icon
    when "running"
      running_icon
    when "preparing"
      pending_icon
    when "uploading"
      running_icon
    when "pending"
      pending_icon
    else
      unknown_icon
    end
  end

  private

  def status_spinner(status)
    return unless status.to_s == "running"

    content_tag(:span, "", class: "inline-block h-3 w-3 rounded-full border-2 border-current border-t-transparent animate-spin")
  end

  def success_icon
    content_tag(:svg, class: "h-5 w-5 text-emerald-600 dark:text-emerald-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end

  def failed_icon
    content_tag(:svg, class: "h-5 w-5 text-red-600 dark:text-red-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
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

  def lost_icon
    content_tag(:svg, class: "h-5 w-5 text-gray-600 dark:text-gray-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m6.364 6.364h.01")
    end
  end

  def unknown_icon
    content_tag(:svg, class: "h-5 w-5 text-gray-600 dark:text-gray-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
      content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
        d: "M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z")
    end
  end
end
