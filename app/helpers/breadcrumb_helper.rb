# frozen_string_literal: true

module BreadcrumbHelper
  # Simple breadcrumb for single-level pages (e.g., "Home / Notifications")
  # Sets both page_title and breadcrumbs content_for blocks
  #
  # @param title [String] The page title to display in breadcrumb
  # @example
  #   <% simple_breadcrumb("Notifications") %>
  def simple_breadcrumb(title)
    content_for(:page_title) { title }
    content_for(:breadcrumbs) do
      safe_join([
        content_tag(:span, "/", class: "mx-2"),
        content_tag(:span, title, class: "font-medium text-slate-700")
      ])
    end
  end

  # Multi-level breadcrumb with intermediate links
  # Sets both page_title and breadcrumbs content_for blocks
  #
  # @param crumbs [Array<Hash>] Array of breadcrumb items with :title and optional :path
  # @example
  #   <% breadcrumb_trail([
  #     { title: "Settings", path: settings_path },
  #     { title: "Agent Releases" }
  #   ]) %>
  def breadcrumb_trail(crumbs)
    return if crumbs.empty?

    # Set page title to the last crumb
    content_for(:page_title) { crumbs.last[:title] }

    content_for(:breadcrumbs) do
      items = crumbs.map.with_index do |crumb, index|
        is_last = index == crumbs.length - 1

        link_or_text = if is_last || crumb[:path].blank?
          content_tag(:span, crumb[:title], class: "font-medium text-slate-700")
        else
          link_to(crumb[:title], crumb[:path], class: "hover:text-teal-600 font-bold")
        end

        safe_join([
          content_tag(:span, "/", class: "mx-2"),
          link_or_text
        ])
      end

      safe_join(items)
    end
  end
end
