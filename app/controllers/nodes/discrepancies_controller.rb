# frozen_string_literal: true

module Nodes
  class DiscrepanciesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_approver!

    def resolve
      node = Node.find(params[:node_id])
      discrepancy = node.inventory_discrepancies.find(params[:id])
      discrepancy.resolve!(note: params[:resolution_note])

      redirect_to node_path(node), notice: "Discrepancy resolved."
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end
  end
end
