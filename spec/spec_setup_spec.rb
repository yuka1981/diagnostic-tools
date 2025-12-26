# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Spec Setup" do
  it "loads Rails environment" do
    expect(Rails.env.test?).to be true
  end

  it "loads RSpec Rails" do
    expect(defined?(RSpec::Rails)).to eq("constant")
  end

  it "loads FactoryBot" do
    expect(defined?(FactoryBot)).to eq("constant")
  end

  it "loads Shoulda Matchers" do
    expect(defined?(Shoulda::Matchers)).to eq("constant")
  end

  it "loads Capybara" do
    expect(defined?(Capybara)).to eq("constant")
  end
end
