# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_presence_of(:password) }
    it { is_expected.to validate_length_of(:password).is_at_least(6) }
  end

  describe "roles" do
    it "defines viewer, requester, and approver roles" do
      expect(User.roles).to eq({ "viewer" => 0, "requester" => 1, "approver" => 2 })
    end

    it "defaults to viewer role" do
      user = User.new
      expect(user.role).to eq("viewer")
    end

    it "can be set to requester" do
      user = build(:user, role: :requester)
      expect(user).to be_requester
    end

    it "can be set to approver" do
      user = build(:user, role: :approver)
      expect(user).to be_approver
    end
  end

  describe "factory" do
    it "creates a valid user" do
      user = build(:user)
      expect(user).to be_valid
    end

    it "creates a valid user with requester trait" do
      user = build(:user, :requester)
      expect(user).to be_valid
      expect(user).to be_requester
    end

    it "creates a valid user with approver trait" do
      user = build(:user, :approver)
      expect(user).to be_valid
      expect(user).to be_approver
    end
  end

  describe "rack_node_preview_fields" do
    it "defaults to cpu, ram, storage, network" do
      user = User.new
      expect(user.rack_node_preview_fields).to eq(%w[cpu ram storage network])
    end

    it "can be set to custom fields" do
      user = build(:user, rack_node_preview_fields: %w[cpu load uptime])
      expect(user.rack_node_preview_fields).to eq(%w[cpu load uptime])
    end

    it "persists the array to the database" do
      user = create(:user, rack_node_preview_fields: %w[ram network])
      user.reload
      expect(user.rack_node_preview_fields).to eq(%w[ram network])
    end

    describe "validation" do
      it "defines VALID_RACK_NODE_PREVIEW_FIELDS constant" do
        expect(User::VALID_RACK_NODE_PREVIEW_FIELDS).to eq(%w[cpu ram storage network load uptime last_seen os tags])
      end

      it "accepts all valid fields" do
        user = build(:user, rack_node_preview_fields: User::VALID_RACK_NODE_PREVIEW_FIELDS)
        expect(user).to be_valid
      end

      it "accepts a subset of valid fields" do
        user = build(:user, rack_node_preview_fields: %w[cpu ram storage])
        expect(user).to be_valid
      end

      it "accepts an empty array" do
        user = build(:user, rack_node_preview_fields: [])
        expect(user).to be_valid
      end

      it "accepts nil" do
        user = build(:user, rack_node_preview_fields: nil)
        expect(user).to be_valid
      end

      it "rejects invalid fields" do
        user = build(:user, rack_node_preview_fields: %w[cpu invalid_field])
        expect(user).not_to be_valid
        expect(user.errors[:rack_node_preview_fields]).to include("contains invalid fields: invalid_field")
      end

      it "rejects multiple invalid fields" do
        user = build(:user, rack_node_preview_fields: %w[cpu bad_field another_bad])
        expect(user).not_to be_valid
        expect(user.errors[:rack_node_preview_fields]).to include("contains invalid fields: bad_field, another_bad")
      end

      it "rejects gpu as an invalid field" do
        user = build(:user, rack_node_preview_fields: %w[cpu gpu])
        expect(user).not_to be_valid
        expect(user.errors[:rack_node_preview_fields]).to include("contains invalid fields: gpu")
      end
    end
  end

  describe "Devise modules" do
    it "includes database_authenticatable" do
      expect(User.devise_modules).to include(:database_authenticatable)
    end

    it "includes registerable" do
      expect(User.devise_modules).to include(:registerable)
    end

    it "includes recoverable" do
      expect(User.devise_modules).to include(:recoverable)
    end

    it "includes rememberable" do
      expect(User.devise_modules).to include(:rememberable)
    end

    it "includes validatable" do
      expect(User.devise_modules).to include(:validatable)
    end
  end
end
