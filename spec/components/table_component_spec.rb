# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe TableComponent, type: :component do
  let(:nodes) do
    [
      OpenStruct.new(id: 1, hostname: "node-1", status: "online"),
      OpenStruct.new(id: 2, hostname: "node-2", status: "offline")
    ]
  end

  it "renders table with columns and rows" do
    render_inline(TableComponent.new(collection: nodes)) do |table|
      table.with_column(header: "Hostname") { |node| node.hostname }
      table.with_column(header: "Status") { |node| node.status }
    end

    expect(page).to have_css("table.min-w-full")
    expect(page).to have_css("thead.bg-neutral-2")
    expect(page).to have_css("th", text: "Hostname")
    expect(page).to have_css("th", text: "Status")
    expect(page).to have_css("td", text: "node-1")
    expect(page).to have_css("td", text: "node-2")
  end

  it "wraps in card-netbox" do
    render_inline(TableComponent.new(collection: nodes)) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("div.card-netbox table")
  end

  it "renders empty state when collection is empty" do
    render_inline(TableComponent.new(collection: [])) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
      table.with_empty do
        '<div class="py-12">No items found</div>'.html_safe
      end
    end

    expect(page).not_to have_css("table")
    expect(page).to have_text("No items found")
  end

  describe "selectable tables" do
    it "renders checkbox column when selectable" do
      render_inline(TableComponent.new(
        collection: nodes,
        selectable: true,
        bulk_action_path: "/nodes/bulk_destroy"
      )) do |table|
        table.with_column(header: "Name") { |n| n.hostname }
      end

      expect(page).to have_css("input[type='checkbox'][data-bulk-select-target='selectAll']")
      expect(page).to have_css("input[type='checkbox'][data-bulk-select-target='checkbox']", count: 2)
    end

    it "renders bulk action bar when selectable" do
      render_inline(TableComponent.new(
        collection: nodes,
        selectable: true,
        bulk_action_path: "/nodes/bulk_destroy"
      )) do |table|
        table.with_bulk_action(label: "Delete", method: :delete, confirm: "Are you sure?")
        table.with_column(header: "Name") { |n| n.hostname }
      end

      expect(page).to have_css("[data-bulk-select-target='actionBar']")
      expect(page).to have_button("Delete")
    end

    it "uses item id for checkbox value" do
      render_inline(TableComponent.new(
        collection: nodes,
        selectable: true,
        bulk_action_path: "/nodes/bulk_destroy"
      )) do |table|
        table.with_column(header: "Name") { |n| n.hostname }
      end

      expect(page).to have_css("input[type='checkbox'][value='1']")
      expect(page).to have_css("input[type='checkbox'][value='2']")
    end
  end

  it "applies hover effect on rows" do
    render_inline(TableComponent.new(collection: nodes)) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("tr.hover\\:bg-neutral-2")
  end
end
