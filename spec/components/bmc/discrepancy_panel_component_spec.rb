# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::DiscrepancyPanelComponent, type: :component do
  let(:node) { create(:node) }

  subject(:component) { described_class.new(node: node) }

  describe "#render" do
    subject(:rendered) { render_inline(component) }

    context "when there are no discrepancies" do
      it "does not render the panel" do
        expect(rendered.css(".card-netbox")).to be_empty
      end
    end

    context "when there are unresolved discrepancies" do
      let!(:critical_discrepancy) do
        create(:inventory_discrepancy, :critical, node: node,
               field_path: "processors.0.serial",
               inband_value: "INBAND-SERIAL",
               bmc_value: "BMC-SERIAL",
               created_at: 2.hours.ago)
      end

      let!(:warning_discrepancy) do
        create(:inventory_discrepancy, :warning, node: node,
               field_path: "memory.0.size",
               inband_value: "16GB",
               bmc_value: "32GB",
               created_at: 1.hour.ago)
      end

      let!(:info_discrepancy) do
        create(:inventory_discrepancy, node: node,
               field_path: "system.vendor",
               inband_value: "Dell Inc.",
               bmc_value: "Dell",
               created_at: 30.minutes.ago)
      end

      it "renders the panel with warning border" do
        expect(rendered.css(".card-netbox.border-warning-2")).to be_present
      end

      it "displays the panel title with discrepancy count" do
        expect(rendered.css(".card-title").text).to include("Inventory Discrepancies")
        expect(rendered.text).to include("3")
      end

      it "shows each discrepancy with severity badge" do
        expect(rendered.text).to include("Critical")
        expect(rendered.text).to include("Warning")
        expect(rendered.text).to include("Info")
      end

      it "displays field path for each discrepancy" do
        expect(rendered.text).to include("processors.0.serial")
        expect(rendered.text).to include("memory.0.size")
        expect(rendered.text).to include("system.vendor")
      end

      it "displays in-band and BMC values" do
        expect(rendered.text).to include("INBAND-SERIAL")
        expect(rendered.text).to include("BMC-SERIAL")
        expect(rendered.text).to include("16GB")
        expect(rendered.text).to include("32GB")
      end

      it "displays resolve button for each discrepancy" do
        # button_to generates either input[type=submit] or button element
        resolve_buttons = rendered.css("input[type='submit'][value='Resolve']").presence ||
                          rendered.css("button:contains('Resolve')").presence
        expect(resolve_buttons.count).to eq(3) if resolve_buttons
        expect(rendered.text.scan("Resolve").count).to be >= 3
      end

      it "orders discrepancies by severity (critical first) then by created_at" do
        divs = rendered.css("div.p-4[id^='inventory_discrepancy']")
        expect(divs.first["id"]).to include(critical_discrepancy.id.to_s)
      end

      context "with critical severity" do
        it "shows error badge styling for critical discrepancy" do
          badge = rendered.css("span.bg-error-1")
          expect(badge).to be_present
          expect(badge.text).to include("Critical")
        end

        it "shows alert-circle icon for critical severity" do
          # The icon class should indicate error color
          critical_div = rendered.css("#inventory_discrepancy_#{critical_discrepancy.id}")
          expect(critical_div.to_html).to include("text-error-6")
        end
      end

      context "with warning severity" do
        it "shows warning badge styling for warning discrepancy" do
          badge = rendered.css("span.bg-warning-1.text-warning-7.border-warning-2")
          expect(badge).to be_present
        end

        it "shows alert-triangle icon for warning severity" do
          warning_div = rendered.css("#inventory_discrepancy_#{warning_discrepancy.id}")
          expect(warning_div.to_html).to include("text-warning-6")
        end
      end

      context "with info severity" do
        it "shows primary badge styling for info discrepancy" do
          badge = rendered.css("span.bg-primary-1")
          expect(badge).to be_present
          expect(badge.text).to include("Info")
        end
      end

      it "displays time ago for each discrepancy" do
        expect(rendered.text).to include("ago")
      end
    end

    context "when there are only resolved discrepancies" do
      before do
        create(:inventory_discrepancy, :resolved, node: node)
      end

      it "does not render the panel" do
        expect(rendered.css(".card-netbox")).to be_empty
      end
    end

    context "when discrepancy has nil inband_value" do
      before do
        create(:inventory_discrepancy, node: node, inband_value: nil, bmc_value: "BMC-VALUE")
      end

      it "displays (none) for inband value" do
        expect(rendered.text).to include("(none)")
        expect(rendered.text).to include("BMC-VALUE")
      end
    end

    context "when discrepancy has nil bmc_value" do
      before do
        create(:inventory_discrepancy, node: node, inband_value: "INBAND-VALUE", bmc_value: nil)
      end

      it "displays (none) for BMC value" do
        expect(rendered.text).to include("INBAND-VALUE")
        expect(rendered.text).to include("(none)")
      end
    end
  end

  describe "#discrepancies" do
    let!(:critical) { create(:inventory_discrepancy, :critical, node: node, created_at: 1.hour.ago) }
    let!(:warning) { create(:inventory_discrepancy, :warning, node: node, created_at: 2.hours.ago) }
    let!(:info) { create(:inventory_discrepancy, node: node, created_at: 30.minutes.ago) }
    let!(:resolved) { create(:inventory_discrepancy, :resolved, node: node) }

    it "returns only unresolved discrepancies" do
      expect(component.discrepancies).not_to include(resolved)
    end

    it "orders by severity descending then by created_at descending" do
      discrepancies = component.discrepancies.to_a
      expect(discrepancies[0]).to eq(critical)
      expect(discrepancies[1]).to eq(warning)
      expect(discrepancies[2]).to eq(info)
    end
  end

  describe "#has_discrepancies?" do
    context "with unresolved discrepancies" do
      before { create(:inventory_discrepancy, node: node) }

      it "returns true" do
        expect(component.has_discrepancies?).to be true
      end
    end

    context "with only resolved discrepancies" do
      before { create(:inventory_discrepancy, :resolved, node: node) }

      it "returns false" do
        expect(component.has_discrepancies?).to be false
      end
    end

    context "with no discrepancies" do
      it "returns false" do
        expect(component.has_discrepancies?).to be false
      end
    end
  end

  describe "#severity_badge_classes" do
    it "returns error styling for critical severity" do
      classes = component.severity_badge_classes(:critical)
      expect(classes).to include("bg-error-1")
      expect(classes).to include("text-error-7")
      expect(classes).to include("border-error-2")
    end

    it "returns warning styling for warning severity" do
      classes = component.severity_badge_classes(:warning)
      expect(classes).to include("bg-warning-1")
      expect(classes).to include("text-warning-7")
      expect(classes).to include("border-warning-2")
    end

    it "returns primary styling for info severity" do
      classes = component.severity_badge_classes(:info)
      expect(classes).to include("bg-primary-1")
      expect(classes).to include("text-primary-7")
      expect(classes).to include("border-primary-2")
    end

    it "returns primary styling for unknown severity" do
      classes = component.severity_badge_classes(:unknown)
      expect(classes).to include("bg-primary-1")
    end
  end

  describe "#severity_icon" do
    it "returns alert-circle for critical severity" do
      expect(component.severity_icon(:critical)).to eq("alert-circle")
    end

    it "returns alert-triangle for warning severity" do
      expect(component.severity_icon(:warning)).to eq("alert-triangle")
    end

    it "returns info for info severity" do
      expect(component.severity_icon(:info)).to eq("info")
    end

    it "returns info for unknown severity" do
      expect(component.severity_icon(:unknown)).to eq("info")
    end
  end
end
