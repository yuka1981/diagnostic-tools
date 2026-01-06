# frozen_string_literal: true

module Benchmark
  class TriggerJob < ApplicationJob
    queue_as :default

    def perform(node, run, server_url, agent_token)
      trigger_service = Benchmark::TriggerRunService.new(
        node,
        log_path: run.log_path,
        run_id: run.uuid,
        server_url: server_url,
        agent_token: agent_token
      )
      result = trigger_service.call

      unless result.success?
        run.update!(status: :failed, error_message: result.error)
      end
    end
  end
end
