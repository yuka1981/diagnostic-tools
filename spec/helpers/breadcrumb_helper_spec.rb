# frozen_string_literal: true

require "rails_helper"

RSpec.describe BreadcrumbHelper, type: :helper do
  describe "#simple_breadcrumb" do
    it "sets page_title content_for" do
      helper.simple_breadcrumb("Notifications")
      expect(helper.content_for(:page_title)).to eq("Notifications")
    end

    it "sets breadcrumbs content_for with separator and title" do
      helper.simple_breadcrumb("Notifications")
      breadcrumbs = helper.content_for(:breadcrumbs)

      expect(breadcrumbs).to include("/")
      expect(breadcrumbs).to include("Notifications")
      expect(breadcrumbs).to include("font-medium")
      expect(breadcrumbs).to include("text-slate-700")
    end
  end

  describe "#breadcrumb_trail" do
    it "returns nil for empty crumbs" do
      expect(helper.breadcrumb_trail([])).to be_nil
    end

    it "sets page_title to the last crumb" do
      helper.breadcrumb_trail([
        { title: "Settings", path: "/settings" },
        { title: "Agent Releases" }
      ])
      expect(helper.content_for(:page_title)).to eq("Agent Releases")
    end

    it "renders intermediate crumbs as links" do
      helper.breadcrumb_trail([
        { title: "Settings", path: "/settings" },
        { title: "Agent Releases" }
      ])
      breadcrumbs = helper.content_for(:breadcrumbs)

      expect(breadcrumbs).to include('href="/settings"')
      expect(breadcrumbs).to include("Settings")
      expect(breadcrumbs).to include("hover:text-teal-600")
    end

    it "renders the last crumb as plain text" do
      helper.breadcrumb_trail([
        { title: "Settings", path: "/settings" },
        { title: "Agent Releases" }
      ])
      breadcrumbs = helper.content_for(:breadcrumbs)

      expect(breadcrumbs).to include("Agent Releases")
      expect(breadcrumbs).to include("font-medium text-slate-700")
    end

    it "handles single crumb" do
      helper.breadcrumb_trail([ { title: "Dashboard" } ])
      breadcrumbs = helper.content_for(:breadcrumbs)

      expect(breadcrumbs).to include("Dashboard")
      expect(helper.content_for(:page_title)).to eq("Dashboard")
    end

    it "handles crumb without path as plain text" do
      helper.breadcrumb_trail([
        { title: "Settings" },
        { title: "Details" }
      ])
      breadcrumbs = helper.content_for(:breadcrumbs)

      # Both should be plain text since neither has a path
      expect(breadcrumbs).not_to include("href=")
    end
  end
end
