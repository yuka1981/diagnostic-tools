# frozen_string_literal: true

module Nodes
  class DiscrepanciesController < ApplicationController
    before_action :authenticate_user!

    def resolve
      node = Node.find(params[:node_id])
      discrepancy = node.inventory_discrepancies.find(params[:id])
      discrepancy.resolve!(note: params[:resolution_note])

      redirect_to node_path(node), notice: "Discrepancy resolved."
    end
  end
end
