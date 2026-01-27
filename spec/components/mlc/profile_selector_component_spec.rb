# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::ProfileSelectorComponent, type: :component do
  it "renders all five profile cards" do
    render_inline(described_class.new(selected: "quick"))

    expect(page).to have_text("Quick")
    expect(page).to have_text("Standard")
    expect(page).to have_text("Full")
    expect(page).to have_text("NUMA")
    expect(page).to have_text("Latency")
  end

  it "marks the selected profile" do
    render_inline(described_class.new(selected: "standard"))

    # Standard should be selected (has ring)
    expect(page).to have_css("input[value='standard'][checked]", visible: :all)
  end

  it "renders section label" do
    render_inline(described_class.new(selected: "quick"))
    expect(page).to have_text("Select Profile")
  end
end
