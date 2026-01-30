# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::ProfileCardComponent, type: :component do
  let(:profile) { Mlc::PROFILES[:quick] }

  it "renders profile name" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("Quick")
  end

  it "renders runtime badge" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("~4 min")
  end

  it "renders description" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("Fast health check")
  end

  it "renders test list" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_text("idle_latency")
    expect(page).to have_text("peak_bandwidth")
  end

  it "includes hidden radio input" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).to have_css("input[type='radio'][name='mlc_run_form[profile]'][value='quick']", visible: :all)
  end

  it "applies selected styling when selected" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: true))
    expect(page).to have_css(".ring-2.ring-primary-5")
  end

  it "does not apply selected styling when not selected" do
    render_inline(described_class.new(key: :quick, profile: profile, selected: false))
    expect(page).not_to have_css(".ring-2.ring-primary-5")
  end
end
