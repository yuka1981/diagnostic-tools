# frozen_string_literal: true

module Profiling
  class TriggerJob < ApplicationJob
    queue_as :default

    def perform(run, server_url, api_token, user_id: nil)
      notification = create_notification(run, user_id)

      service = Profiling::TriggerService.new(run, server_url: server_url, api_token: api_token)
      result = service.call

      # Reload to check current state - status may have changed during execution
      # (e.g., user cancelled, or agent already reported completion)
      run.reload
      return if run.status != "pending"

      if result.success?
        run.update!(status: :running, started_at: Time.current, log_content: result.output)
        complete_notification(notification, success: true, message: "Profiling started successfully")
      else
        run.update!(status: :failed, error_message: result.error, log_content: result.output)
        complete_notification(notification, success: false, message: result.error)
      end
    rescue StandardError => e
      complete_notification(notification, success: false, message: e.message)
      raise
    end

    private

    def create_notification(run, user_id)
      return nil if user_id.blank?

      user = User.find_by(id: user_id)
      return nil unless user

      notification = NotificationService.create(
        user: user,
        type: "profiling",
        title: "Running profiling on #{run.node.hostname}",
        resource: run
      )
      NotificationService.start(notification)
      notification
    end

    def complete_notification(notification, success:, message:)
      return unless notification

      NotificationService.complete(notification, success: success, message: message)
    end
  end
end
