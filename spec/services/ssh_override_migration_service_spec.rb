# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshOverrideMigrationService do
  describe ".migrate_existing_nodes" do
    it "enables ssh_user_override for nodes with ssh_user set" do
      node = create(:node, ssh_user: "custom_user", ssh_user_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_user_override).to be true
    end

    it "enables ssh_port_override for nodes with non-default ssh_port" do
      node = create(:node, ssh_port: 2222, ssh_port_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_port_override).to be true
    end

    it "does not enable ssh_port_override for nodes with default port 22" do
      node = create(:node, ssh_port: 22, ssh_port_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_port_override).to be false
    end

    it "enables ssh_key_override for nodes with ssh_key set" do
      node = create(:node, ssh_key: "some-private-key", ssh_key_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_key_override).to be true
    end

    it "enables ssh_password_override for nodes with ssh_password set" do
      node = create(:node, ssh_password: "secret", ssh_password_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_password_override).to be true
    end

    it "enables sudo_credential_override for nodes with sudo_credential set" do
      node = create(:node, sudo_credential: "sudo-pass", sudo_credential_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.sudo_credential_override).to be true
    end

    it "enables ssh_connect_method_override for nodes with direct connection" do
      node = create(:node, ssh_connect_method: :direct, ssh_connect_method_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_connect_method_override).to be true
    end

    it "does not enable ssh_connect_method_override for nodes with global_bastion (default)" do
      node = create(:node, ssh_connect_method: :global_bastion, ssh_connect_method_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_connect_method_override).to be false
    end

    it "does not change nodes that already have overrides enabled" do
      node = create(:node, ssh_user: "custom", ssh_user_override: true)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_user_override).to be true
    end

    it "does not enable overrides for nodes with blank values" do
      node = create(:node, ssh_user: nil, ssh_user_override: false)

      described_class.migrate_existing_nodes

      node.reload
      expect(node.ssh_user_override).to be false
    end
  end
end
