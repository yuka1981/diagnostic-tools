# frozen_string_literal: true

module NodesHelper
  def group_memory_topology(memory_devices)
    memory_devices ||= []

    # v2 Flexible Grouper: Extract Socket and Channel
    # Strategy: Match CPU#, P#, Socket#, Node#
    memory_devices.each_with_object({}) do |dev, acc|
      bank = dev["bank_locator"] || ""

      # Extract Socket (CPU 0, P0, etc.)
      socket_match = bank.match(/(CPU\s?\d+|P\d+|Socket\s?\d+|Node\s?\d+)/i)
      socket_name = socket_match ? socket_match[0].upcase.gsub(/\s+/, "") : "System"

      # Extract Channel (Channel 0, CH0, etc.)
      channel_match = bank.match(/(Channel\s?\d+|CH\d+|NODE\d+)/i)
      channel_name = channel_match ? channel_match[0].upcase.gsub(/\s+/, "") : "Default"

      acc[socket_name] ||= {}
      acc[socket_name][channel_name] ||= []
      acc[socket_name][channel_name] << dev
    end
  end

  def format_socket_name(socket)
    socket.gsub(/^(P|NODE)(\d+)$/i, 'CPU \2')
  end

  def memory_slot_status_classes(slot)
    installed = slot["size"] && slot["size"] != "No Module Installed"
    spec_speed = slot["speed"]&.scan(/\d+/)&.first&.to_i || 0
    config_speed = slot["configured_speed"]&.scan(/\d+/)&.first&.to_i || 0
    downgraded = installed && config_speed > 0 && spec_speed > 0 && config_speed < spec_speed

    if !installed
      "bg-neutral-2 border-dashed border-2 border-neutral-8 text-neutral-15"
    elsif downgraded
      "bg-amber-50 border-2 border-amber-400 text-amber-800"
    else
      "bg-primary-6 border-2 border-primary-7 text-white shadow-sm"
    end
  end

  def memory_slot_downgraded?(slot)
    installed = slot["size"] && slot["size"] != "No Module Installed"
    spec_speed = slot["speed"]&.scan(/\d+/)&.first&.to_i || 0
    config_speed = slot["configured_speed"]&.scan(/\d+/)&.first&.to_i || 0
    installed && config_speed > 0 && spec_speed > 0 && config_speed < spec_speed
  end

  def net_interface_status_badge(status)
    case status.to_s.downcase
    when "up", "active"
      content_tag :span, "Active", class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold bg-success-5 text-white shadow-sm uppercase tracking-wider"
    when "down"
      content_tag :span, "Down", class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold bg-error-5 text-white shadow-sm uppercase tracking-wider"
    else
      content_tag :span, status.to_s.upcase, class: "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold bg-neutral-45 text-white shadow-sm uppercase tracking-wider"
    end
  end
end
