module ApplicationHelper
  include DashboardHelper

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
end
