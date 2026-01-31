# frozen_string_literal: true

module Nodes
  class NetworkController < ApplicationController
    before_action :set_node

    def ib_details
      @state = if params[:state_id].present?
                 @node.node_states.find(params[:state_id])
      else
                 @node.current_state
      end

      if @state && @state.network_inventory.present?
        @interface = @state.network_inventory["devices"]&.find { |i| i["name"] == params[:interface_name] }
      end

      render partial: "nodes/ib_details", locals: { interface: @interface }
    end

    private

    def set_node
      @node = Node.find(params[:node_id])
    end
  end
end
