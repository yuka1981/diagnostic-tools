# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlideOverComponent, type: :component do
  it "renders with title" do
    render_inline(SlideOverComponent.new(title: "Run Details")) do |panel|
      panel.with_tab(name: "Summary", active: true) { "Summary content" }
    end

    expect(page).to have_css("h2", text: "Run Details")
  end

  it "renders backdrop and panel" do
    render_inline(SlideOverComponent.new(title: "Details")) do |panel|
      panel.with_tab(name: "Info", active: true) { "Content" }
    end

    expect(page).to have_css("[data-slide-over-target='backdrop']")
    expect(page).to have_css("[data-slide-over-target='panel']")
  end

  it "renders header badge slot" do
    render_inline(SlideOverComponent.new(title: "Run #123")) do |panel|
      panel.with_header_badge { '<span class="badge">Success</span>'.html_safe }
      panel.with_tab(name: "Summary", active: true) { "Content" }
    end

    expect(page).to have_css("span.badge", text: "Success")
  end

  it "renders close button" do
    render_inline(SlideOverComponent.new(title: "Details")) do |panel|
      panel.with_tab(name: "Info", active: true) { "Content" }
    end

    expect(page).to have_css("[data-slide-over-target='closeButton']")
    expect(page).to have_css("button[data-action='click->slide-over#close']")
  end

  describe "tabs" do
    it "renders multiple tabs" do
      render_inline(SlideOverComponent.new(title: "Details")) do |panel|
        panel.with_tab(name: "Summary", active: true) { "Summary content" }
        panel.with_tab(name: "Metrics") { "Metrics content" }
        panel.with_tab(name: "Logs") { "Logs content" }
      end

      expect(page).to have_css("button[role='tab']", count: 3)
      expect(page).to have_css("button", text: "Summary")
      expect(page).to have_css("button", text: "Metrics")
      expect(page).to have_css("button", text: "Logs")
    end

    it "marks active tab with correct styling" do
      render_inline(SlideOverComponent.new(title: "Details")) do |panel|
        panel.with_tab(name: "Summary", active: true) { "Summary" }
        panel.with_tab(name: "Other") { "Other" }
      end

      expect(page).to have_css("button[aria-selected='true']", text: "Summary")
      expect(page).to have_css("button[aria-selected='false']", text: "Other")
    end

    it "renders tab panels with visibility" do
      render_inline(SlideOverComponent.new(title: "Details")) do |panel|
        panel.with_tab(name: "Summary", active: true) { "Summary content" }
        panel.with_tab(name: "Other") { "Other content" }
      end

      expect(page).to have_css("[role='tabpanel'][aria-hidden='false']", text: "Summary content")
      expect(page).to have_css("[role='tabpanel'][aria-hidden='true'].hidden", text: "Other content")
    end
  end

  it "uses tabs stimulus controller" do
    render_inline(SlideOverComponent.new(title: "Details")) do |panel|
      panel.with_tab(name: "Tab", active: true) { "Content" }
    end

    expect(page).to have_css("[data-controller='tabs']")
  end

  describe "test IDs" do
    it "renders data-testid on container when testid is provided" do
      render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
        c.with_tab(name: "Overview", active: true) { "Content" }
      end

      expect(page).to have_css("[data-testid='nodes-modal-container']")
    end

    it "renders data-testid on header" do
      render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
        c.with_tab(name: "Overview", active: true) { "Content" }
      end

      expect(page).to have_css("[data-testid='nodes-modal-header']")
    end

    it "renders data-testid on close button" do
      render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
        c.with_tab(name: "Overview", active: true) { "Content" }
      end

      expect(page).to have_css("[data-testid='nodes-modal-close-button']")
    end

    it "renders data-testid on tabs container" do
      render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
        c.with_tab(name: "Overview", active: true) { "Content" }
        c.with_tab(name: "Hardware", active: false) { "Content" }
      end

      expect(page).to have_css("[data-testid='nodes-modal-tabs']")
    end

    it "renders data-testid on content area" do
      render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
        c.with_tab(name: "Overview", active: true) { "Content" }
      end

      expect(page).to have_css("[data-testid='nodes-modal-content']")
    end

    it "does not render data-testid when testid is not provided" do
      render_inline(SlideOverComponent.new(title: "Details")) do |c|
        c.with_tab(name: "Overview", active: true) { "Content" }
      end

      expect(page).not_to have_css("[data-testid]")
    end
  end
end
