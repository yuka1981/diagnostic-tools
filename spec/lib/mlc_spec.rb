# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc do
  describe "::PROFILES" do
    it "defines five profiles" do
      expect(Mlc::PROFILES.keys).to contain_exactly(:quick, :standard, :full, :numa, :latency)
    end

    it "each profile has required keys" do
      Mlc::PROFILES.each do |name, profile|
        expect(profile).to have_key(:name), "#{name} missing :name"
        expect(profile).to have_key(:runtime), "#{name} missing :runtime"
        expect(profile).to have_key(:description), "#{name} missing :description"
        expect(profile).to have_key(:tests), "#{name} missing :tests"
      end
    end

    it "quick profile includes idle_latency and peak_bandwidth tests" do
      expect(Mlc::PROFILES[:quick][:tests]).to include("idle_latency", "peak_bandwidth")
    end
  end
end
