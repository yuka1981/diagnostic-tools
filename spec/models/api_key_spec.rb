require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe "token generation" do
    it "generates a token on creation" do
      key = ApiKey.create!(name: "Test Key")
      expect(key.token).to be_present
      expect(key.token.length).to eq(48) # hex(24) is 48 chars
    end

    it "does not overwrite existing token" do
      key = ApiKey.create!(name: "Test Key", token: "existing-token")
      expect(key.token).to eq("existing-token")
    end
  end

  describe "status" do
    it "defaults to active" do
      key = ApiKey.new
      expect(key.status).to eq("active")
    end
  end

  describe "#touch_last_used" do
    it "updates last_used_at" do
      key = create(:api_key)
      expect { key.touch_last_used }.to change { key.last_used_at }
    end
  end
end
