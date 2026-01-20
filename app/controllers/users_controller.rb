# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!

  def update_preferences
    if current_user.update(preferences_params)
      respond_to do |format|
        format.turbo_stream { head :ok }
        format.json { render json: { success: true } }
        format.html { head :ok }
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.json { render json: { success: false, errors: current_user.errors.full_messages }, status: :unprocessable_entity }
        format.html { head :unprocessable_entity }
      end
    end
  end

  private

  def preferences_params
    # Handle empty array case - Rails sends [""] for empty arrays, so filter out blank values
    if params.key?(:rack_node_preview_fields)
      fields = Array(params[:rack_node_preview_fields]).reject(&:blank?)
      { rack_node_preview_fields: fields }
    else
      {}
    end
  end
end
