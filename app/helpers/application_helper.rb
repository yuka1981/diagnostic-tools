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
    return "—" if mbps.blank?

    "#{mbps} Mbps"
  end
end
