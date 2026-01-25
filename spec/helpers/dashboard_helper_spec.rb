# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardHelper, type: :helper do
  describe "#status_badge_class" do
    it "returns success colors for success status" do
      expect(helper.status_badge_class("success")).to include("success")
    end

    it "returns success colors for completed status" do
      expect(helper.status_badge_class("completed")).to include("success")
    end

    it "returns success colors for online status" do
      expect(helper.status_badge_class("online")).to include("success")
    end

    it "returns error colors for failed status" do
      expect(helper.status_badge_class("failed")).to include("error")
    end

    it "returns error colors for offline status" do
      expect(helper.status_badge_class("offline")).to include("error")
    end

    it "returns running colors for running status" do
      expect(helper.status_badge_class("running")).to include("blue")
    end

    it "returns warning colors for pending status" do
      expect(helper.status_badge_class("pending")).to include("yellow")
    end

    it "returns muted colors for cancelled status" do
      expect(helper.status_badge_class("cancelled")).to include("neutral")
    end

    it "returns warning colors for unknown status" do
      # "unknown" maps to :warning in STATUS_COLORS
      expect(helper.status_badge_class("unknown")).to include("yellow")
    end

    it "returns default muted colors for unrecognized status" do
      # Unrecognized statuses fall back to DEFAULT_BADGE_CLASS (muted/neutral)
      expect(helper.status_badge_class("unknown_status")).to include("neutral")
    end

    it "handles symbol status" do
      expect(helper.status_badge_class(:success)).to include("success")
    end
  end

  describe "#status_bg_class" do
    it "returns success background for success status" do
      expect(helper.status_bg_class("success")).to include("success")
    end

    it "returns error background for failed status" do
      expect(helper.status_bg_class("failed")).to include("error")
    end

    it "returns warning background for unknown status" do
      # "unknown" maps to :warning which uses yellow color
      expect(helper.status_bg_class("unknown")).to include("yellow")
    end

    it "returns default background for unrecognized status" do
      expect(helper.status_bg_class("unrecognized_status")).to include("neutral")
    end
  end

  describe "#status_text_color" do
    it "returns success text color for success status" do
      expect(helper.status_text_color("success")).to include("success")
    end

    it "returns error text color for failed status" do
      expect(helper.status_text_color("failed")).to include("error")
    end

    it "returns warning text color for unknown status" do
      # "unknown" maps to :warning which uses yellow color
      expect(helper.status_text_color("unknown")).to include("yellow")
    end

    it "returns default text color for unrecognized status" do
      expect(helper.status_text_color("unrecognized_status")).to include("neutral")
    end
  end

  describe "#role_badge_class" do
    it "returns blue for compute role" do
      expect(helper.role_badge_class("compute")).to include("blue")
    end

    it "returns purple for login role" do
      expect(helper.role_badge_class("login")).to include("purple")
    end

    it "returns amber for admin role" do
      expect(helper.role_badge_class("admin")).to include("amber")
    end

    it "returns default for unknown role" do
      expect(helper.role_badge_class("unknown")).to include("neutral")
    end

    it "handles symbol role" do
      expect(helper.role_badge_class(:compute)).to include("blue")
    end
  end

  describe "#node_heatmap_class" do
    # Node status is computed from last_heartbeat_at, not a status attribute
    let(:online_compute_node) { build(:node, role: :compute, last_heartbeat_at: 1.minute.ago) }
    let(:offline_compute_node) { build(:node, role: :compute, last_heartbeat_at: 10.minutes.ago) }
    let(:online_login_node) { build(:node, role: :login, last_heartbeat_at: 1.minute.ago) }
    let(:online_admin_node) { build(:node, role: :admin, last_heartbeat_at: 1.minute.ago) }

    it "returns emerald for online compute nodes" do
      expect(helper.node_heatmap_class(online_compute_node)).to include("emerald")
    end

    it "returns neutral for offline compute nodes" do
      expect(helper.node_heatmap_class(offline_compute_node)).to include("neutral")
    end

    it "returns blue for online login nodes" do
      expect(helper.node_heatmap_class(online_login_node)).to include("blue")
    end

    it "returns amber for online admin nodes" do
      expect(helper.node_heatmap_class(online_admin_node)).to include("amber")
    end
  end

  # Note: ApplicationHelper also defines status_icon and includes DashboardHelper,
  # so the actual method called depends on helper include order.
  # These tests verify the ApplicationHelper version which takes precedence in views.
  describe "#status_icon" do
    it "returns success icon for success status" do
      result = helper.status_icon("success")
      expect(result).to include("success")
      expect(result).to include("<svg")
    end

    it "returns failed icon for failed status" do
      result = helper.status_icon("failed")
      expect(result).to include("error")
      expect(result).to include("<svg")
    end

    it "returns running icon for running status" do
      result = helper.status_icon("running")
      expect(result).to include("blue")
      expect(result).to include("animate-spin")
    end

    it "returns pending icon for pending status" do
      result = helper.status_icon("pending")
      expect(result).to include("neutral")
      expect(result).to include("<svg")
    end

    it "returns neutral icon for cancelled status" do
      result = helper.status_icon("cancelled")
      expect(result).to include("neutral")
      expect(result).to include("<svg")
    end

    it "returns neutral icon for unrecognized status" do
      result = helper.status_icon("something_else")
      expect(result).to include("neutral")
      expect(result).to include("<svg")
    end
  end
end
