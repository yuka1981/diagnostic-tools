# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFieldComponent, type: :component do
  let(:node) { Node.new }
  let(:form) do
    view = ActionView::Base.empty
    view.extend(ActionView::Helpers::FormHelper)
    view.extend(ActionView::Helpers::FormTagHelper)
    ActionView::Helpers::FormBuilder.new(:node, node, view, {})
  end

  it "renders label and text field" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname"
    ))

    expect(page).to have_css("label", text: "Hostname")
    expect(page).to have_css("input[type='text'][name='node[hostname]']")
  end

  it "renders hint text" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      hint: "Enter the server hostname"
    ))

    expect(page).to have_css("p.text-xs.text-neutral-45", text: "Enter the server hostname")
  end

  it "renders placeholder" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      placeholder: "e.g., compute-001"
    ))

    expect(page).to have_css("input[placeholder='e.g., compute-001']")
  end

  it "renders required indicator" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      required: true
    ))

    expect(page).to have_css("span.text-error-5", text: "*")
  end

  it "renders custom input via slot" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :role,
      label: "Role"
    )) do |field|
      field.with_input do
        '<select name="node[role]"><option>compute</option></select>'.html_safe
      end
    end

    expect(page).to have_css("select[name='node[role]']")
    expect(page).not_to have_css("input[type='text']")
  end

  it "applies error styling when model has errors" do
    node.errors.add(:hostname, "can't be blank")

    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname"
    ))

    expect(page).to have_css("input.border-error-3")
    expect(page).to have_css("p.text-error-6", text: "can't be blank")
  end

  it "exposes input_classes method" do
    component = FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname"
    )

    expect(component.input_classes).to include("rounded-md")
    expect(component.input_classes).to include("border-neutral-15")
  end

  describe "test IDs" do
    it "renders data-testid on container when testid is provided" do
      render_inline(FormFieldComponent.new(
        form: form,
        attribute: :hostname,
        label: "Hostname",
        testid: "nodes-field-hostname"
      ))

      expect(page).to have_css("[data-testid='nodes-field-hostname']")
    end

    it "renders data-testid on error container when errors present" do
      node.errors.add(:hostname, "can't be blank")

      render_inline(FormFieldComponent.new(
        form: form,
        attribute: :hostname,
        label: "Hostname",
        testid: "nodes-field-hostname"
      ))

      expect(page).to have_css("[data-testid='nodes-field-hostname-error']")
    end

    it "does not render data-testid when testid is not provided" do
      render_inline(FormFieldComponent.new(
        form: form,
        attribute: :hostname,
        label: "Hostname"
      ))

      expect(page).not_to have_css("[data-testid]")
    end
  end
end
