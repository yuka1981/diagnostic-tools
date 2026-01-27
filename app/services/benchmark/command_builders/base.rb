# frozen_string_literal: true

require "shellwords"

module Benchmark
  module CommandBuilders
    # Base class for benchmark command builders
    class Base
      attr_reader :run_id, :node_uuid, :agent_bin, :arguments, :server_url, :token, :log_path

      def initialize(run_id:, node_uuid:, agent_bin:, arguments: nil, server_url: nil, token: nil, log_path: nil)
        @run_id = run_id
        @node_uuid = node_uuid
        @agent_bin = agent_bin
        @arguments = arguments || {}
        @server_url = server_url
        @token = token
        @log_path = log_path
      end

      def build
        raise NotImplementedError, "#{self.class} must implement #build"
      end

      protected

      def subcommand
        raise NotImplementedError, "#{self.class} must implement #subcommand"
      end

      def base_command
        "env OMP_NUM_THREADS=$(nproc) #{esc(agent_bin)} --node-uuid #{esc(node_uuid)} #{subcommand} --id #{esc(run_id)}"
      end

      def append_common_flags(command)
        flags = []
        flags << "--server #{esc(server_url)}" if server_url.present?
        flags << "--token #{esc(token)}" if token.present?
        return command if flags.empty?

        "#{command} #{flags.join(' ')}"
      end

      def esc(value)
        Shellwords.escape(value.to_s)
      end
    end
  end
end
