# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatusBadgeComponent, type: :component do
  describe "status variants" do
    it "renders success variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :success))

      expect(page).to have_css("span.bg-success-2.text-success-7.border-success-2")
      expect(page).to have_text("Success")
    end

    it "renders error variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :error))

      expect(page).to have_css("span.bg-error-1.text-error-7.border-error-2")
      expect(page).to have_text("Error")
    end

    it "renders running variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :running))

      expect(page).to have_css("span.bg-primary-1.text-primary-7.border-primary-2")
      expect(page).to have_text("Running")
    end

    it "renders warning variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :warning))

      expect(page).to have_css("span.bg-warning-1.text-warning-7.border-warning-2")
      expect(page).to have_text("Warning")
    end

    it "renders muted variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :muted))

      expect(page).to have_css("span.bg-neutral-4.text-neutral-85.border-neutral-8")
      expect(page).to have_text("Muted")
    end

    it "falls back to muted for unknown status" do
      render_inline(StatusBadgeComponent.new(status: :unknown_status))

      expect(page).to have_css("span.bg-neutral-4")
    end
  end

  describe "custom label" do
    it "uses custom label when provided" do
      render_inline(StatusBadgeComponent.new(status: :success, label: "Active"))

      expect(page).to have_text("Active")
      expect(page).not_to have_text("Success")
    end
  end

  describe "status string mapping" do
    it "maps 'completed' to success variant" do
      render_inline(StatusBadgeComponent.new(status: "completed"))

      expect(page).to have_css("span.bg-success-2")
    end

    it "maps 'failed' to error variant" do
      render_inline(StatusBadgeComponent.new(status: "failed"))

      expect(page).to have_css("span.bg-error-1")
    end

    it "maps 'pending' to warning variant" do
      render_inline(StatusBadgeComponent.new(status: "pending"))

      expect(page).to have_css("span.bg-warning-1")
    end

    it "maps 'cancelled' to muted variant" do
      render_inline(StatusBadgeComponent.new(status: "cancelled"))

      expect(page).to have_css("span.bg-neutral-4")
    end
  end

  describe "size variants" do
    it "renders default size" do
      render_inline(StatusBadgeComponent.new(status: :success))

      expect(page).to have_css("span.px-2.py-0\\.5.text-xs")
    end

    it "renders small size" do
      render_inline(StatusBadgeComponent.new(status: :success, size: :small))

      expect(page).to have_css("span.px-1\\.5.py-0\\.5.text-\\[9px\\]")
    end
  end

  describe "test IDs" do
    it "renders data-testid when testid is provided" do
      render_inline(StatusBadgeComponent.new(status: :success, testid: "nodes-badge-status"))

      expect(page).to have_css("[data-testid='nodes-badge-status-success']")
    end

    it "does not render data-testid when testid is not provided" do
      render_inline(StatusBadgeComponent.new(status: :success))

      expect(page).not_to have_css("[data-testid]")
    end
  end
end
