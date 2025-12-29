# frozen_string_literal: true

class NodesController < ApplicationController
  layout "dashboard"

  def index
    @nodes = Node.order(:hostname)
  end

  def show
    @node = Node.find(params[:id])
  end
end
