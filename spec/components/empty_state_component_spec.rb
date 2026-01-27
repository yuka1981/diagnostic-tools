# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmptyStateComponent, type: :component do
  it "renders with icon, title, and description" do
    render_inline(EmptyStateComponent.new(
      icon: "inbox",
      title: "No items found",
      description: "Get started by creating your first item."
    ))

    expect(page).to have_css("div.flex.flex-col.items-center.justify-center.py-12")
    expect(page).to have_text("No items found")
    expect(page).to have_text("Get started by creating your first item.")
  end

  it "renders action slot content" do
    render_inline(EmptyStateComponent.new(
      icon: "server",
      title: "No nodes",
      description: "Add a node to get started."
    )) do |component|
      component.with_action do
        '<a href="/nodes/new" class="btn-primary">Add Node</a>'.html_safe
      end
    end

    expect(page).to have_css("div.mt-6.flex.gap-3")
    expect(page).to have_link("Add Node", href: "/nodes/new")
  end

  it "renders without description" do
    render_inline(EmptyStateComponent.new(
      icon: "file",
      title: "No files"
    ))

    expect(page).to have_text("No files")
    expect(page).not_to have_css("p.mt-1")
  end

  it "renders with custom icon classes" do
    render_inline(EmptyStateComponent.new(
      icon: "alert-circle",
      title: "Error",
      icon_class: "text-error-5"
    ))

    expect(page).to have_css("svg.text-error-5") | have_css("[data-lucide='alert-circle']")
  end
end
