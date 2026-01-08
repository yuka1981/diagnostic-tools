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
    base_classes = "px-2 py-0.5 rounded text-xs font-bold shadow-sm text-white"

    color_classes = case status.to_s
    when "online", "success", "passed"
      "bg-emerald-500"
    when "offline", "failed", "error"
      "bg-red-500"
    when "running"
      "bg-blue-500 animate-pulse"
    when "unknown", "warning"
      "bg-yellow-500"
    else
      "bg-slate-500"
    end

    "#{base_classes} #{color_classes}"
  end
end
