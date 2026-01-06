# frozen_string_literal: true

class ApiKeysController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :authorize_approver!
  before_action :set_api_key, only: [ :revoke, :destroy ]

  def index
    @api_keys = ApiKey.order(created_at: :desc)
  end

  def new
    @api_key = ApiKey.new
  end

  def create
    @api_key = ApiKey.new(api_key_params)

    if @api_key.save
      redirect_to api_keys_path, notice: "API Key was successfully created. Copy your token now: #{@api_key.token}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def revoke
    @api_key.revoked!
    redirect_to api_keys_path, notice: "API Key was successfully revoked."
  end

  def destroy
    if @api_key.revoked?
      @api_key.destroy
      redirect_to api_keys_path, notice: "API Key was successfully deleted."
    else
      redirect_to api_keys_path, alert: "Only revoked API keys can be deleted."
    end
  end

  private

  def authorize_approver!
    return if current_user.approver?

    redirect_to root_path, alert: "You are not authorized to manage API keys."
  end

  def set_api_key
    @api_key = ApiKey.find(params[:id])
  end

  def api_key_params
    params.require(:api_key).permit(:name)
  end
end
