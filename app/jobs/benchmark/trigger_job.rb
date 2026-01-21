# frozen_string_literal: true

module Benchmark
  class TriggerJob < ApplicationJob
    queue_as :default

    def perform(node, run, server_url, agent_token, argument_overrides = {}, user_id: nil)
      notification = nil

      # Create notification if user_id is provided
      if user_id.present?
        user = User.find_by(id: user_id)
        if user
          notification = NotificationService.create(
            user: user,
            type: "benchmark",
            title: "Running benchmark on #{node.hostname}",
            resource: run
          )
          NotificationService.start(notification)
        end
      end

      trigger_service = Benchmark::TriggerRunService.new(
        node,
        log_path: run.log_path,
        run_id: run.uuid,
        server_url: server_url,
        agent_token: agent_token,
        benchmark_recipe: run.benchmark_recipe,
        argument_overrides: argument_overrides
      )
      result = trigger_service.call

      # Reload to check current state - status may have changed during SSH call
      # (e.g., user cancelled, or fast agent already reported completion)
      run.reload
      unless run.pending?
        # Run state changed externally, mark notification accordingly
        NotificationService.complete(notification, success: run.completed?, message: "Benchmark #{run.status}") if notification
        return
      end

      if result.success?
        # Optimistically mark as running since SSH command was accepted
        # Agent will update to success/failed when complete
        run.update!(status: :running, started_at: Time.current, log_content: result.output)
        NotificationService.complete(notification, success: true, message: "Benchmark started successfully") if notification
      else
        # Store both error message and full SSH output for debugging
        run.update!(status: :failed, error_message: result.error, log_content: result.output)
        NotificationService.complete(notification, success: false, message: result.error) if notification
      end
    rescue => e
      NotificationService.complete(notification, success: false, message: e.message) if notification
      raise
    end
  end
end
