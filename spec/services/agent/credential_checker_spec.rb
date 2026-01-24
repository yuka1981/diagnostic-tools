# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::CredentialChecker do
  let(:node) { create(:node) }

  describe "#needs_ssh_password?" do
    context "when node has SSH key" do
      before { node.update!(ssh_key: "private-key-content", ssh_key_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be false
      end
    end

    context "when global SSH key is configured" do
      before { SshSetting.current.update!(ssh_key: "global-key") }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be false
      end
    end

    context "when node has stored SSH password" do
      before { node.update!(ssh_password: "secret", ssh_password_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be false
      end
    end

    context "when no SSH key or password configured" do
      before do
        node.update!(ssh_key: nil, ssh_password: nil, ssh_key_override: false, ssh_password_override: false)
        SshSetting.current.update!(ssh_key: nil)
      end

      it "returns true" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_ssh_password?).to be true
      end
    end
  end

  describe "#needs_sudo_credential?" do
    context "when SSH user is root" do
      before { node.update!(ssh_user: "root", ssh_user_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be false
      end
    end

    context "when global SSH user is root" do
      before do
        node.update!(ssh_user_override: false)
        SshSetting.current.update!(ssh_user: "root")
      end

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be false
      end
    end

    context "when node has stored sudo credential" do
      before { node.update!(sudo_credential: "sudo-pass", sudo_credential_override: true) }

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be false
      end
    end

    context "when non-root user without stored credential" do
      before do
        node.update!(ssh_user: "admin", ssh_user_override: true, sudo_credential: nil, sudo_credential_override: false)
        SshSetting.current.update!(ssh_user: nil)
      end

      it "returns true" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_sudo_credential?).to be true
      end
    end
  end

  describe "#needs_api_key?" do
    context "for install operation" do
      context "when node has API key assigned" do
        let(:api_key) { create(:api_key) }
        before { node.update!(api_key: api_key) }

        it "returns false" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_api_key?).to be false
        end
      end

      context "when node has no API key" do
        before { node.update!(api_key_id: nil) }

        it "returns true" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_api_key?).to be true
        end
      end
    end

    context "for update operation" do
      it "returns false regardless of API key" do
        node.update!(api_key_id: nil)
        checker = described_class.new(node, operation: :update)
        expect(checker.needs_api_key?).to be false
      end
    end

    context "for uninstall operation" do
      it "returns false regardless of API key" do
        node.update!(api_key_id: nil)
        checker = described_class.new(node, operation: :uninstall)
        expect(checker.needs_api_key?).to be false
      end
    end
  end

  describe "#needs_server_url?" do
    context "for install operation" do
      context "when global server URL is set" do
        before { SshSetting.current.update!(server_url: "https://example.com") }

        it "returns false" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_server_url?).to be false
        end
      end

      context "when global server URL is blank" do
        before { SshSetting.current.update!(server_url: nil) }

        it "returns true" do
          checker = described_class.new(node, operation: :install)
          expect(checker.needs_server_url?).to be true
        end
      end
    end

    context "for update operation" do
      before { SshSetting.current.update!(server_url: nil) }

      it "returns false" do
        checker = described_class.new(node, operation: :update)
        expect(checker.needs_server_url?).to be false
      end
    end
  end

  describe "#needs_modal?" do
    context "when all credentials are configured" do
      let(:api_key) { create(:api_key) }

      before do
        node.update!(
          ssh_key: "key", ssh_key_override: true,
          ssh_user: "root", ssh_user_override: true,
          api_key: api_key
        )
        SshSetting.current.update!(server_url: "https://example.com")
      end

      it "returns false" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_modal?).to be false
      end
    end

    context "when any credential is missing" do
      before do
        node.update!(ssh_key: nil, ssh_key_override: false, ssh_password: nil, ssh_password_override: false)
        SshSetting.current.update!(ssh_key: nil)
      end

      it "returns true" do
        checker = described_class.new(node, operation: :install)
        expect(checker.needs_modal?).to be true
      end
    end
  end

  describe "#required_fields" do
    it "returns hash of required fields" do
      checker = described_class.new(node, operation: :install)
      fields = checker.required_fields

      expect(fields).to be_a(Hash)
      expect(fields.keys).to contain_exactly(:ssh_password, :sudo_password, :api_key, :server_url)
    end
  end
end
