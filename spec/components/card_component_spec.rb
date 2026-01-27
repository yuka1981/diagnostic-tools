# frozen_string_literal: true

require "rails_helper"

RSpec.describe CardComponent, type: :component do
  it "renders with title and content" do
    render_inline(CardComponent.new(title: "Test Card")) do
      "Card content here"
    end

    expect(page).to have_css("div.card-netbox")
    expect(page).to have_css("div.card-header")
    expect(page).to have_css("h3.card-title", text: "Test Card")
    expect(page).to have_text("Card content here")
  end

  it "renders action slot in header" do
    render_inline(CardComponent.new(title: "Nodes")) do |card|
      card.with_action do
        '<a href="/nodes/new" class="btn-primary">Add</a>'.html_safe
      end
      "Content"
    end

    expect(page).to have_css("div.card-header")
    expect(page).to have_link("Add", href: "/nodes/new")
  end

  it "renders without header when title is nil" do
    render_inline(CardComponent.new) do
      "Just content"
    end

    expect(page).to have_css("div.card-netbox")
    expect(page).not_to have_css("div.card-header")
    expect(page).to have_text("Just content")
  end

  it "renders with padding by default" do
    render_inline(CardComponent.new(title: "Padded")) do
      "Content"
    end

    expect(page).to have_css("div.p-4")
  end

  it "renders without padding when padding: false" do
    render_inline(CardComponent.new(title: "No Padding", padding: false)) do
      "Table goes here"
    end

    expect(page).not_to have_css("div.p-4")
  end

  it "accepts custom CSS classes" do
    render_inline(CardComponent.new(title: "Custom", class: "mt-4")) do
      "Content"
    end

    expect(page).to have_css("div.card-netbox.mt-4")
  end
end
