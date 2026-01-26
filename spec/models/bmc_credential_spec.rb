# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmcCredential, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node).optional }
  end

  describe "validations" do
    subject { build(:bmc_credential) }

    it { is_expected.to validate_presence_of(:bmc_address) }
    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:password) }

    describe "global_default constraints" do
      context "when is_global_default is true" do
        it "requires node_id to be nil" do
          node = create(:node)
          credential = build(:bmc_credential, :global_default, node: node)
          expect(credential).not_to be_valid
          expect(credential.errors[:node_id]).to include("must be nil for global default credential")
        end

        it "is valid when node_id is nil" do
          credential = build(:bmc_credential, :global_default, node: nil)
          expect(credential).to be_valid
        end
      end

      context "when is_global_default is false" do
        it "allows node_id to be present" do
          node = create(:node)
          credential = build(:bmc_credential, node: node)
          expect(credential).to be_valid
        end

        it "allows node_id to be nil" do
          credential = build(:bmc_credential, node: nil)
          expect(credential).to be_valid
        end
      end
    end

    describe "uniqueness of global_default" do
      it "allows only one global default credential" do
        create(:bmc_credential, :global_default)
        duplicate = build(:bmc_credential, :global_default)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:is_global_default]).to include("has already been taken")
      end

      it "allows multiple non-global credentials" do
        create(:bmc_credential)
        credential = build(:bmc_credential)
        expect(credential).to be_valid
      end
    end

    describe "uniqueness of node_id" do
      it "allows only one credential per node" do
        node = create(:node)
        create(:bmc_credential, node: node)
        duplicate = build(:bmc_credential, node: node)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:node_id]).to include("has already been taken")
      end

      it "allows multiple credentials with nil node_id" do
        create(:bmc_credential, node: nil)
        credential = build(:bmc_credential, node: nil)
        expect(credential).to be_valid
      end
    end
  end

  describe "enums" do
    describe "protocol" do
      it "defines auto, redfish, and ipmi protocols" do
        expect(described_class.protocols).to eq({ "auto" => 0, "redfish" => 1, "ipmi" => 2 })
      end

      it "defaults to auto protocol" do
        credential = described_class.new
        expect(credential.protocol).to eq("auto")
      end

      it "can be set to redfish" do
        credential = build(:bmc_credential, :redfish)
        expect(credential).to be_redfish
      end

      it "can be set to ipmi" do
        credential = build(:bmc_credential, :ipmi)
        expect(credential).to be_ipmi
      end
    end
  end

  describe "encryption" do
    it "encrypts username" do
      credential = create(:bmc_credential, username: "admin_user")
      # Reload from database and check that the encrypted value differs
      raw_value = ActiveRecord::Base.connection.execute(
        "SELECT username FROM bmc_credentials WHERE id = #{credential.id}"
      ).first["username"]
      expect(raw_value).not_to eq("admin_user")
    end

    it "encrypts password" do
      credential = create(:bmc_credential, password: "secret_password")
      # Reload from database and check that the encrypted value differs
      raw_value = ActiveRecord::Base.connection.execute(
        "SELECT password FROM bmc_credentials WHERE id = #{credential.id}"
      ).first["password"]
      expect(raw_value).not_to eq("secret_password")
    end

    it "decrypts username when accessed" do
      credential = create(:bmc_credential, username: "admin_user")
      credential.reload
      expect(credential.username).to eq("admin_user")
    end

    it "decrypts password when accessed" do
      credential = create(:bmc_credential, password: "secret_password")
      credential.reload
      expect(credential.password).to eq("secret_password")
    end
  end

  describe "scopes" do
    describe ".global_default" do
      let!(:global_credential) { create(:bmc_credential, :global_default) }
      let!(:node_credential) { create(:bmc_credential, node: create(:node)) }

      it "returns only the global default credential" do
        expect(described_class.global_default).to eq([ global_credential ])
      end
    end
  end

  describe ".global_default (class method)" do
    context "when a global default exists" do
      let!(:global_credential) { create(:bmc_credential, :global_default) }

      it "returns the global default credential" do
        expect(described_class.global_default_record).to eq(global_credential)
      end
    end

    context "when no global default exists" do
      it "returns nil" do
        expect(described_class.global_default_record).to be_nil
      end
    end
  end

  describe "factory" do
    it "creates a valid bmc_credential" do
      credential = build(:bmc_credential)
      expect(credential).to be_valid
    end

    it "creates a valid credential with global_default trait" do
      credential = build(:bmc_credential, :global_default)
      expect(credential).to be_valid
      expect(credential.is_global_default).to be true
      expect(credential.node).to be_nil
    end

    it "creates a valid credential with redfish trait" do
      credential = build(:bmc_credential, :redfish)
      expect(credential).to be_valid
      expect(credential).to be_redfish
    end

    it "creates a valid credential with ipmi trait" do
      credential = build(:bmc_credential, :ipmi)
      expect(credential).to be_valid
      expect(credential).to be_ipmi
    end
  end
end
