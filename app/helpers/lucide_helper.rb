# frozen_string_literal: true

module LucideHelper
  def lucide_icon(name, options = {})
    icon_data = lucide_icons[name.to_s]
    return content_tag(:span, "?", title: "Unknown icon: #{name}") unless icon_data

    css_class = options.delete(:class) || "w-5 h-5"
    stroke_width = options.delete(:stroke_width) || 2

    content_tag(:svg,
      class: css_class,
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": stroke_width,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      **options
    ) do
      render_icon_elements(icon_data)
    end
  end

  private

  def lucide_icons
    @lucide_icons ||= YAML.load_file(Rails.root.join("config/lucide_icons.yml"))
  end

  def render_icon_elements(icon_data)
    elements = []

    # Render paths
    icon_data["paths"]&.each do |d|
      elements << tag(:path, d: d)
    end

    # Render rectangles
    icon_data["rects"]&.each do |rect|
      elements << tag(:rect, rect.symbolize_keys)
    end

    # Render lines
    icon_data["lines"]&.each do |line|
      elements << tag(:line, line.symbolize_keys)
    end

    # Render circles
    icon_data["circles"]&.each do |circle|
      elements << tag(:circle, circle.symbolize_keys)
    end

    safe_join(elements)
  end
end
