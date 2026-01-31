# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmcCredential, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:bmc_address) }
    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:password) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:protocol).with_values(auto: 0, redfish: 1, ipmi: 2) }
  end

  describe "encryption" do
    it "encrypts the password attribute" do
      credential = create(:bmc_credential, password: "secret123")
      raw = BmcCredential.connection.select_value(
        "SELECT password FROM bmc_credentials WHERE id = #{credential.id}"
      )
      expect(raw).not_to eq("secret123")
      expect(credential.reload.password).to eq("secret123")
    end
  end

  describe ".global_default" do
    it "returns the global default credential" do
      global = create(:bmc_credential, :global_default)
      create(:bmc_credential, node: create(:node))
      expect(BmcCredential.global_default).to eq(global)
    end
  end

  describe ".for_node" do
    let(:node) { create(:node) }

    it "returns node-specific credential when present" do
      node_cred = create(:bmc_credential, node: node)
      create(:bmc_credential, :global_default)
      expect(BmcCredential.for_node(node)).to eq(node_cred)
    end

    it "falls back to global default when no node-specific credential" do
      global = create(:bmc_credential, :global_default)
      expect(BmcCredential.for_node(node)).to eq(global)
    end

    it "returns nil when no credential exists" do
      expect(BmcCredential.for_node(node)).to be_nil
    end
  end
end
