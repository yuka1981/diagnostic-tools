# frozen_string_literal: true

module Benchmark
  class TriggerJob < ApplicationJob
    queue_as :default

    def perform(node, run, argument_overrides = {}, user_id: nil)
      notification = create_notification(node, run, user_id) if user_id

      service = Benchmark::SaltTriggerRunService.new(
        node,
        benchmark_run: run,
        argument_overrides: argument_overrides
      )

      result = service.call

      if result.success?
        complete_notification(notification, :success, "Benchmark started on #{node.hostname}")
      else
        complete_notification(notification, :failure, "Failed: #{result.error}")
      end
    rescue StandardError => e
      run.update!(status: :failed, error_message: e.message, finished_at: Time.current) unless run.completed?
      complete_notification(notification, :failure, "Error: #{e.message}")
      raise
    end

    private

    def create_notification(node, run, user_id)
      return nil unless user_id.present?
      user = User.find_by(id: user_id)
      return nil unless user
      NotificationService.create(
        user: user,
        type: "benchmark",
        title: "Running benchmark on #{node.hostname}",
        resource: run
      )
    rescue StandardError
      nil
    end

    def complete_notification(notification, status, message)
      return unless notification
      NotificationService.complete(notification, success: status == :success, message: message)
    rescue StandardError
      nil
    end
  end
end
