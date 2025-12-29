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
