# frozen_string_literal: true

require "rails_helper"

RSpec.describe SaltSetting, type: :model do
  describe ".current" do
    it "creates a default record when none exists" do
      expect { SaltSetting.current }.to change(SaltSetting, :count).from(0).to(1)
    end

    it "returns the existing record" do
      existing = SaltSetting.create!(base_url: "http://salt:8000")
      expect(SaltSetting.current).to eq(existing)
    end

    it "defaults verify_ssl to true via database default" do
      setting = SaltSetting.current
      expect(setting.verify_ssl).to be true
    end

    it "does not overwrite existing verify_ssl value" do
      SaltSetting.create!(verify_ssl: false)
      setting = SaltSetting.current
      expect(setting.verify_ssl).to be false
    end
  end

  describe "validations" do
    it "allows http URLs" do
      setting = SaltSetting.new(base_url: "http://salt-master:8000")
      setting.valid?
      expect(setting.errors[:base_url]).to be_empty
    end

    it "allows https URLs" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000")
      setting.valid?
      expect(setting.errors[:base_url]).to be_empty
    end

    it "rejects URLs with paths" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000/api")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must be a base URL without path (e.g., https://salt-master:8000)")
    end

    it "rejects non-http schemes" do
      setting = SaltSetting.new(base_url: "ftp://salt-master:8000")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must use http or https scheme")
    end

    it "rejects URLs with query parameters" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000?foo=bar")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must not contain query parameters")
    end

    it "rejects URLs with fragments" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000#section")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must not contain URL fragments")
    end

    it "allows blank base_url" do
      setting = SaltSetting.new(base_url: "")
      setting.valid?
      expect(setting.errors[:base_url]).to be_empty
    end
  end

  describe "#configured?" do
    it "returns true when base_url, username, and password are present" do
      setting = SaltSetting.new(base_url: "http://salt:8000", username: "admin", password: "secret")
      expect(setting.configured?).to be true
    end

    it "returns false when base_url is blank" do
      setting = SaltSetting.new(username: "admin", password: "secret")
      expect(setting.configured?).to be false
    end

    it "returns false when username is blank" do
      setting = SaltSetting.new(base_url: "http://salt:8000", password: "secret")
      expect(setting.configured?).to be false
    end

    it "returns false when password is blank" do
      setting = SaltSetting.new(base_url: "http://salt:8000", username: "admin")
      expect(setting.configured?).to be false
    end
  end
end
