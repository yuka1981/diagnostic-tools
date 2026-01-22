# frozen_string_literal: true

require "rails_helper"

RSpec.describe NodeFormWizardComponent, type: :component do
  let(:node) { build(:node) }
  let(:ssh_profiles) { [] }
  let(:api_keys) { [] }
  let(:agent_config) { nil }

  subject(:component) do
    described_class.new(
      node: node,
      ssh_profiles: ssh_profiles,
      api_keys: api_keys,
      agent_config: agent_config
    )
  end

  describe "#render" do
    subject(:rendered) { render_inline(component) }

    it "renders wizard with 3 steps" do
      expect(rendered.css("[data-wizard-target='step']").length).to eq(3)
    end

    it "renders progress indicators for 3 steps" do
      expect(rendered.css("[data-wizard-target='indicator']").length).to eq(3)
    end

    it "renders wizard controller with correct values" do
      wizard_div = rendered.css("[data-controller='wizard']").first
      expect(wizard_div).to be_present
      expect(wizard_div["data-wizard-total-value"]).to eq("3")
    end

    context "step 1 (Basic Info)" do
      it "has hostname field" do
        step1 = rendered.css("[data-wizard-target='step']").first
        expect(step1.css("input[name='node[hostname]']")).to be_present
      end

      it "has role select" do
        step1 = rendered.css("[data-wizard-target='step']").first
        expect(step1.css("select[name='node[role]']")).to be_present
      end

      it "has arch select" do
        step1 = rendered.css("[data-wizard-target='step']").first
        expect(step1.css("select[name='node[arch]']")).to be_present
      end

      it "has ip field" do
        step1 = rendered.css("[data-wizard-target='step']").first
        expect(step1.css("input[name='node[ip]']")).to be_present
      end
    end

    context "step 2 (Server & Location)" do
      it "has server-product-search controller" do
        step2 = rendered.css("[data-wizard-target='step']")[1]
        expect(step2.css("[data-controller*='server-product-search']")).to be_present
      end

      it "has server_product_id hidden field" do
        step2 = rendered.css("[data-wizard-target='step']")[1]
        expect(step2.css("input[name='node[server_product_id]']")).to be_present
      end

      it "has rack_id select" do
        step2 = rendered.css("[data-wizard-target='step']")[1]
        expect(step2.css("select[name='node[rack_id]']")).to be_present
      end
    end

    context "step 3 (Connection)" do
      it "has ssh_profile_id select" do
        step3 = rendered.css("[data-wizard-target='step']")[2]
        expect(step3.css("select[name='node[ssh_profile_id]']")).to be_present
      end

      it "has api_key_id select" do
        step3 = rendered.css("[data-wizard-target='step']")[2]
        expect(step3.css("select[name='node[api_key_id]']")).to be_present
      end

      it "has agent_path field" do
        step3 = rendered.css("[data-wizard-target='step']")[2]
        expect(step3.css("input[name='node[agent_path]']")).to be_present
      end
    end

    context "navigation buttons" do
      it "has back button" do
        expect(rendered.css("[data-wizard-target='backButton']")).to be_present
      end

      it "has next button" do
        expect(rendered.css("[data-wizard-target='nextButton']")).to be_present
      end

      it "has submit button" do
        expect(rendered.css("[data-wizard-target='submitButton']")).to be_present
      end
    end

    context "form action" do
      context "with new node" do
        let(:node) { build(:node) }

        it "submits to nodes_path" do
          form = rendered.css("form").first
          expect(form["action"]).to eq("/nodes")
        end
      end

      context "with persisted node" do
        let(:node) { create(:node) }

        it "submits to node_path" do
          form = rendered.css("form").first
          expect(form["action"]).to eq("/nodes/#{node.id}")
        end
      end
    end
  end

  describe "#roles_for_select" do
    it "returns roles mapped to titleize" do
      roles = component.send(:roles_for_select)
      expect(roles).to include([ "Compute", "compute" ])
      expect(roles).to include([ "Login", "login" ])
      expect(roles).to include([ "Admin", "admin" ])
    end
  end

  describe "#architectures_for_select" do
    it "returns architecture options" do
      archs = component.send(:architectures_for_select)
      expect(archs).to include([ "x86_64", "x86_64" ])
      expect(archs).to include([ "ARM64", "aarch64" ])
    end
  end

  describe "#form_method" do
    context "with new node" do
      let(:node) { build(:node) }

      it "returns :post" do
        expect(component.send(:form_method)).to eq(:post)
      end
    end

    context "with persisted node" do
      let(:node) { create(:node) }

      it "returns :patch" do
        expect(component.send(:form_method)).to eq(:patch)
      end
    end
  end

  describe "#ssh_profiles_for_select" do
    let(:ssh_profiles) { create_list(:ssh_profile, 2) }

    it "returns profiles mapped to [name, id]" do
      profiles = component.send(:ssh_profiles_for_select)
      expect(profiles.length).to eq(2)
      expect(profiles.first).to eq([ ssh_profiles.first.name, ssh_profiles.first.id ])
    end
  end

  describe "#api_keys_for_select" do
    let(:api_keys) { create_list(:api_key, 2) }

    it "returns keys mapped to [name, id]" do
      keys = component.send(:api_keys_for_select)
      expect(keys.length).to eq(2)
      expect(keys.first).to eq([ api_keys.first.name, api_keys.first.id ])
    end
  end

  describe "#default_agent_path" do
    context "with agent_config" do
      let(:agent_config) { double(default_agent_path: "/custom/path/agent") }

      it "returns path from agent_config" do
        expect(component.send(:default_agent_path)).to eq("/custom/path/agent")
      end
    end

    context "without agent_config" do
      let(:agent_config) { nil }

      it "returns constant default" do
        expect(component.send(:default_agent_path)).to eq(SshSetting::DEFAULT_AGENT_PATH)
      end
    end
  end
end
