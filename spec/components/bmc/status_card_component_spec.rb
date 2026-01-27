# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::StatusCardComponent, type: :component do
  let(:node) { create(:node) }

  subject(:component) { described_class.new(node: node) }

  describe "#render" do
    subject(:rendered) { render_inline(component) }

    context "when BMC is configured" do
      before do
        node.update!(bmc_address: "10.0.1.100")
      end

      it "renders the card with BMC Status title" do
        expect(rendered.css(".card-netbox")).to be_present
        expect(rendered.css(".card-title").text).to include("BMC Status")
      end

      it "displays the BMC address" do
        expect(rendered.text).to include("10.0.1.100")
      end

      it "displays protocol label" do
        expect(rendered.text).to include("Protocol")
        expect(rendered.text).to include("Auto")
      end

      it "has Collect Now button" do
        # button_to can generate either input[type=submit] or button element
        collect_button = rendered.css("input[type='submit'][value='Collect Now']").presence ||
                         rendered.css("button:contains('Collect Now')").presence
        expect(collect_button || rendered.text.include?("Collect Now")).to be_truthy
      end

      context "with latest inventory" do
        let!(:inventory) { create(:bmc_inventory, node: node, captured_at: 1.hour.ago) }

        it "displays last collected timestamp" do
          expect(rendered.text).to include("ago")
        end

        it "shows health status badge" do
          expect(rendered.css(".card-header span")).to be_present
        end

        context "with OK health status" do
          let!(:inventory) do
            create(:bmc_inventory, node: node, bmc_info: { "health" => "OK" })
          end

          it "displays health badge with success styling" do
            badge = rendered.css(".card-header span").first
            expect(badge["class"]).to include("bg-success-2")
            expect(badge.text.strip).to eq("Ok")
          end
        end

        context "with warning health status" do
          let!(:inventory) do
            create(:bmc_inventory, node: node, bmc_info: { "health" => "Warning" })
          end

          it "displays health badge with warning styling" do
            badge = rendered.css(".card-header span").first
            expect(badge["class"]).to include("bg-warning-1")
            expect(badge.text.strip).to eq("Warning")
          end
        end

        context "with critical health status" do
          let!(:inventory) do
            create(:bmc_inventory, node: node, bmc_info: { "health" => "Critical" })
          end

          it "displays health badge with error styling" do
            badge = rendered.css(".card-header span").first
            expect(badge["class"]).to include("bg-error-1")
            expect(badge.text.strip).to eq("Critical")
          end
        end
      end

      context "without inventory" do
        it "shows 'Never' for last collected" do
          expect(rendered.text).to include("Never")
        end

        it "does not show health status badge" do
          expect(rendered.css(".card-header span")).to be_empty
        end
      end

      context "with discrepancies" do
        before do
          create_list(:inventory_discrepancy, 2, node: node)
        end

        it "shows discrepancy count" do
          expect(rendered.text).to include("2 unresolved")
        end

        it "shows discrepancy row in table" do
          expect(rendered.text).to include("Discrepancies")
        end
      end

      context "without discrepancies" do
        it "does not show discrepancy row" do
          expect(rendered.text).not_to include("Discrepancies")
          expect(rendered.text).not_to include("unresolved")
        end
      end

      context "with node-specific BMC credential" do
        before do
          create(:bmc_credential, node: node, protocol: :redfish)
        end

        it "displays the protocol from credential" do
          expect(rendered.text).to include("Redfish")
        end
      end
    end

    context "when BMC is not configured" do
      before do
        node.update!(bmc_address: nil)
      end

      it "shows 'No BMC configured' message" do
        expect(rendered.text).to include("No BMC configured")
      end

      it "shows help text about adding BMC address" do
        expect(rendered.text).to include("Add a BMC address to enable out-of-band management")
      end

      it "does not show Collect button" do
        expect(rendered.css("input[type='submit'][value='Collect Now']")).to be_empty
      end

      it "does not show address table" do
        expect(rendered.text).not_to include("Address")
        expect(rendered.text).not_to include("Protocol")
      end
    end
  end

  describe "#bmc_configured?" do
    context "when bmc_address is present" do
      before { node.update!(bmc_address: "10.0.1.100") }

      it "returns true" do
        expect(component.bmc_configured?).to be true
      end
    end

    context "when bmc_address is blank" do
      before { node.update!(bmc_address: nil) }

      it "returns false" do
        expect(component.bmc_configured?).to be false
      end
    end
  end

  describe "#health_status" do
    before { node.update!(bmc_address: "10.0.1.100") }

    context "with no inventory" do
      it "returns :unknown" do
        expect(component.health_status).to eq(:unknown)
      end
    end

    context "with inventory without health info" do
      before { create(:bmc_inventory, node: node, bmc_info: {}) }

      it "returns :ok as default" do
        expect(component.health_status).to eq(:ok)
      end
    end

    context "with inventory with health OK" do
      before { create(:bmc_inventory, node: node, bmc_info: { "health" => "OK" }) }

      it "returns :ok" do
        expect(component.health_status).to eq(:ok)
      end
    end

    context "with inventory with health Critical" do
      before { create(:bmc_inventory, node: node, bmc_info: { "health" => "Critical" }) }

      it "returns :critical" do
        expect(component.health_status).to eq(:critical)
      end
    end
  end

  describe "#health_badge_classes" do
    before { node.update!(bmc_address: "10.0.1.100") }

    context "when health is ok" do
      before { create(:bmc_inventory, node: node, bmc_info: { "health" => "OK" }) }

      it "includes success classes" do
        expect(component.health_badge_classes).to include("bg-success-2")
        expect(component.health_badge_classes).to include("text-success-7")
      end
    end

    context "when health is warning" do
      before { create(:bmc_inventory, node: node, bmc_info: { "health" => "Warning" }) }

      it "includes warning classes" do
        expect(component.health_badge_classes).to include("bg-warning-1")
        expect(component.health_badge_classes).to include("text-warning-7")
      end
    end

    context "when health is critical" do
      before { create(:bmc_inventory, node: node, bmc_info: { "health" => "Critical" }) }

      it "includes error classes" do
        expect(component.health_badge_classes).to include("bg-error-1")
        expect(component.health_badge_classes).to include("text-error-7")
      end
    end

    context "when health is unknown" do
      it "includes neutral classes" do
        expect(component.health_badge_classes).to include("bg-neutral-4")
        expect(component.health_badge_classes).to include("text-neutral-85")
      end
    end
  end

  describe "#protocol_label" do
    before { node.update!(bmc_address: "10.0.1.100") }

    context "without any credentials" do
      it "returns 'Auto'" do
        expect(component.protocol_label).to eq("Auto")
      end
    end

    context "with node-specific credential" do
      before { create(:bmc_credential, node: node, protocol: :ipmi) }

      it "returns humanized protocol" do
        expect(component.protocol_label).to eq("Ipmi")
      end
    end

    context "with global default credential" do
      before { create(:bmc_credential, node: nil, is_global_default: true, protocol: :redfish) }

      it "returns humanized protocol from global default" do
        expect(component.protocol_label).to eq("Redfish")
      end
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

  describe "#unresolved_discrepancy_count" do
    context "with mixed discrepancies" do
      before do
        create_list(:inventory_discrepancy, 3, node: node)
        create_list(:inventory_discrepancy, 2, :resolved, node: node)
      end

      it "counts only unresolved discrepancies" do
        expect(component.unresolved_discrepancy_count).to eq(3)
      end
    end
  end
end
