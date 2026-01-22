# frozen_string_literal: true

module Profiling
  class TriggerService
    Result = Struct.new(:success, :output, :error, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(profiling_run, server_url:, api_token:)
      @run = profiling_run
      @server_url = server_url
      @api_token = api_token
    end

    def call
      extra_vars = build_extra_vars
      playbook = playbook_for_subcommand(@run.subcommand)

      result = Ansible::ExecutorService.new(
        admin_config: ansible_admin_config,
        playbook: playbook,
        extra_vars: extra_vars
      ).call

      if result.success?
        Result.new(success: true, output: result.output)
      else
        Result.new(success: false, error: result.error, output: result.output)
      end
    end

    private

    def build_extra_vars
      {
        target_host: @run.node.hostname,
        run_uuid: @run.uuid,
        api_server: @server_url,
        api_token: @api_token,
        shared_artifacts_path: profiling_artifacts_path,
        options: @run.options,
        perfspect_module: @run.profiling_recipe&.module_name || default_module
      }
    end

    def playbook_for_subcommand(subcommand)
      case subcommand
      when "report" then "perfspect/report.yml"
      when "telemetry" then "perfspect/telemetry.yml"
      when "flame" then "perfspect/flame.yml"
      else raise ArgumentError, "Unknown subcommand: #{subcommand}"
      end
    end

    def ansible_admin_config
      {
        host: profiling_settings[:ansible_admin_host],
        user: profiling_settings[:ansible_admin_user],
        playbooks_path: profiling_settings[:playbooks_path]
      }
    end

    def profiling_settings
      @profiling_settings ||= {
        ansible_admin_host: ENV.fetch("ANSIBLE_ADMIN_HOST", "localhost"),
        ansible_admin_user: ENV.fetch("ANSIBLE_ADMIN_USER", "ansible"),
        playbooks_path: ENV.fetch("ANSIBLE_PLAYBOOKS_PATH", Rails.root.join("ansible").to_s)
      }
    end

    def profiling_artifacts_path
      ENV.fetch("PROFILING_ARTIFACTS_PATH", "/shared/profiling_artifacts")
    end

    def default_module
      ENV.fetch("DEFAULT_PERFSPECT_MODULE", "perfspect/3.13.0")
    end
  end
end
