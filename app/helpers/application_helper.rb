module ApplicationHelper
  include DashboardHelper
  include BreadcrumbHelper
  include LucideHelper

  def format_bytes(bytes)
    return "—" if bytes.blank? || bytes.to_i.zero?

    units = [ "B", "KB", "MB", "GB", "TB", "PB" ]
    i = (Math.log(bytes) / Math.log(1024)).floor
    i = units.length - 1 if i >= units.length

    sprintf("%.2f %s", bytes.to_f / (1024**i), units[i])
  end

  def format_megabits(mbps)
    return "—" if mbps.blank? || mbps.to_i <= 0

    if mbps.to_i >= 1000
      sprintf("%.1f Gbps", mbps.to_f / 1000)
    else
      "#{mbps} Mbps"
    end
  end

  def node_status_badge(status)
    base_classes = "px-2 py-0.5 rounded text-xs font-bold shadow-sm"

    color_class = case status.to_s
    when "online", "success", "passed"
      "bg-green-100 text-green-800 border border-green-200"
    when "offline", "failed", "error"
      "bg-red-100 text-red-800 border border-red-200"
    when "running"
      "bg-blue-100 text-blue-800 border border-blue-200 animate-pulse"
    when "unknown", "warning"
      "bg-yellow-100 text-yellow-800 border border-yellow-200"
    else
      "bg-slate-100 text-slate-700 border border-slate-200"
    end

    content_tag(:span, status.to_s.humanize, class: "#{base_classes} #{color_class}")
  end

  def disk_usage_percentage(disk)
    return 0 if disk["total"].to_i.zero?

    (disk["used"].to_f / disk["total"].to_f * 100).round(1)
  end

  def disk_usage_bar_color(percentage)
    if percentage > 90
      "bg-red-500"
    elsif percentage > 75
      "bg-amber-500"
    else
      "bg-blue-500"
    end
  end

  # Format benchmark metric keys for display
  # Handles common abbreviations and converts snake_case to Title Case
  def format_metric_key(key)
    key_str = key.to_s

    # Handle common abbreviations
    abbreviations = {
      "gflops" => "GFLOP/s",
      "gflop_s" => "GFLOP/s",
      "tflops" => "TFLOP/s",
      "gb_s" => "GB/s",
      "mb_s" => "MB/s",
      "cpu" => "CPU",
      "gpu" => "GPU",
      "mpi" => "MPI",
      "omp" => "OpenMP"
    }

    # Check for exact match first
    return abbreviations[key_str.downcase] if abbreviations[key_str.downcase]

    # Otherwise humanize and handle partial matches
    humanized = key_str.humanize.titleize

    # Replace common terms with proper formatting
    humanized
      .gsub(/\bGflops?\b/i, "GFLOP/s")
      .gsub(/\bTflops?\b/i, "TFLOP/s")
      .gsub(/\bCpu\b/, "CPU")
      .gsub(/\bGpu\b/, "GPU")
      .gsub(/\bMpi\b/, "MPI")
      .gsub(/\bOmp\b/, "OpenMP")
  end

  # CSS classes for notification status badges
  def notification_status_badge_class(status)
    case status.to_s
    when "completed"
      "bg-green-100 text-green-800"
    when "failed"
      "bg-red-100 text-red-800"
    when "running"
      "bg-blue-100 text-blue-800"
    when "pending"
      "bg-yellow-100 text-yellow-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  # Render status icon partial for notifications
  def render_status_icon(status, css_class: "w-4 h-4 mr-1")
    icon_name = case status.to_s
    when "pending"
      "clock"
    when "running"
      "spinner"
    when "completed"
      "check_circle"
    when "failed"
      "x_circle"
    else
      "clock"
    end

    animation_class = status.to_s == "running" ? "#{css_class} animate-spin" : css_class
    render partial: "notifications/icons/#{icon_name}", locals: { class: animation_class }
  end

  # Icon for benchmark run status
  def status_icon(status)
    case status.to_s
    when "success"
      lucide_icon("circle-check", class: "h-6 w-6 text-green-500")
    when "failed"
      lucide_icon("circle-x", class: "h-6 w-6 text-red-500")
    when "running"
      lucide_icon("loader-2", class: "h-6 w-6 text-blue-500 animate-spin")
    when "pending"
      lucide_icon("clock", class: "h-6 w-6 text-slate-400")
    else
      lucide_icon("help-circle", class: "h-6 w-6 text-slate-400")
    end
  end
end
