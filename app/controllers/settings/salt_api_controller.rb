# frozen_string_literal: true

module Settings
  class SaltApiController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def show
      @salt_setting = SaltSetting.current
      @webhook_url = webhook_url
    end

    def update
      @salt_setting = SaltSetting.current
      update_params = salt_params.to_h

      # Handle password: clear if flag set, otherwise preserve existing when blank
      if update_params.delete(:clear_password) == "1"
        update_params[:password] = nil
      elsif update_params[:password].blank?
        update_params.delete(:password)
      end

      if @salt_setting.update(update_params)
        redirect_to settings_salt_api_path, notice: "Salt API settings updated successfully."
      else
        @webhook_url = webhook_url
        render :show, status: :unprocessable_entity
      end
    end

    def test_connection
      @salt_setting = SaltSetting.current

      unless @salt_setting.configured?
        @test_result = { success: false, message: "Salt API is not configured. Please fill in the connection settings first." }
        render turbo_stream: turbo_stream.replace("test-connection-result", partial: "settings/salt_api/test_result")
        return
      end

      begin
        client = SaltApiClient.new(
          base_url: @salt_setting.base_url,
          username: @salt_setting.username,
          password: @salt_setting.password,
          verify_ssl: @salt_setting.verify_ssl,
          ca_cert: @salt_setting.ca_cert_path
        )
        client.authenticate
        minions = client.get_minions
        minion_count = minions.keys.size
        @test_result = { success: true, message: "Connected successfully. #{minion_count} minions online." }
      rescue SaltApiClient::AuthenticationError => e
        @test_result = { success: false, message: "Authentication failed: #{e.message}" }
      rescue SaltApiClient::TimeoutError => e
        @test_result = { success: false, message: "Connection timed out: #{e.message}" }
      rescue StandardError => e
        @test_result = { success: false, message: "Failed to connect: #{e.message}" }
      end

      render turbo_stream: turbo_stream.replace("test-connection-result", partial: "settings/salt_api/test_result")
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end

    def webhook_url
      "#{request.base_url}/api/v1/salt/events"
    end

    def salt_params
      params.require(:salt_setting).permit(
        :base_url, :username, :password, :ca_cert_path, :verify_ssl,
        :clear_password
      )
    end
  end
end
