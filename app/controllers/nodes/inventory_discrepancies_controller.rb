# frozen_string_literal: true

class Nodes::InventoryDiscrepanciesController < ApplicationController
  before_action :set_node
  before_action :set_discrepancy

  def resolve
    @discrepancy.update!(
      resolved_at: Time.current,
      resolution_note: params[:resolution_note] || "Manually resolved by user"
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(@discrepancy)
      end
      format.html { redirect_to @node, notice: "Discrepancy resolved" }
    end
  end

  private

  def set_node
    @node = Node.find(params[:node_id])
  end

  def set_discrepancy
    @discrepancy = @node.inventory_discrepancies.find(params[:id])
  end
end
