# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::AdvancedOptionsComponent, type: :component do
  let(:form) { Mlc::RunForm.new }

  it "renders binary path field" do
    render_inline(described_class.new(form: form))
    expect(page).to have_text("MLC Binary Path")
    expect(page).to have_css("input[name='mlc_run_form[binary_path]']")
  end

  it "renders modules field" do
    render_inline(described_class.new(form: form))
    expect(page).to have_text("Lmod Modules")
    expect(page).to have_css("input[name='mlc_run_form[modules]']")
  end

  it "renders log path field" do
    render_inline(described_class.new(form: form))
    expect(page).to have_text("Custom Log Path")
    expect(page).to have_css("input[name='mlc_run_form[log_path]']")
  end

  it "is collapsed by default" do
    render_inline(described_class.new(form: form))
    expect(page).to have_css("[data-collapsible-target='content'].hidden")
  end
end
