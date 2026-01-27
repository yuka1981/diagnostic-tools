# frozen_string_literal: true

module Benchmark
  module CommandBuilders
    # Command builder for HPCG benchmarks
    class HpcgCommandBuilder < Base
      DEFAULT_BUILD_CMD = "make arch=Linux_OpenMP"
      DEFAULT_RUN_CMD = "./bin/xhpcg"
      DEFAULT_TIMEOUT = 60

      def subcommand
        "hpcg"
      end

      def build
        [
          "env OMP_NUM_THREADS=$(nproc)",
          agent_bin,
          "--node-uuid #{node_uuid}",
          subcommand,
          "--id #{run_id}",
          "--build \"#{build_cmd}\"",
          "--run \"#{run_cmd}\"",
          "--rt #{timeout}",
          nx_flag,
          ny_flag,
          nz_flag,
          log_path_flag,
          server_flag,
          token_flag
        ].compact.join(" ")
      end

      private

      def build_cmd
        arguments["build"] || DEFAULT_BUILD_CMD
      end

      def run_cmd
        arguments["run"] || DEFAULT_RUN_CMD
      end

      def timeout
        arguments["rt"] || arguments["timeout"] || DEFAULT_TIMEOUT
      end

      def nx
        arguments["nx"]
      end

      def ny
        arguments["ny"]
      end

      def nz
        arguments["nz"]
      end

      def nx_flag
        "--nx=#{nx}" if nx.present?
      end

      def ny_flag
        "--ny=#{ny}" if ny.present?
      end

      def nz_flag
        "--nz=#{nz}" if nz.present?
      end

      def log_path
        arguments["log_path"]&.presence
      end

      def log_path_flag
        "--log-path #{log_path}" if log_path.present?
      end

      def server_flag
        "--server #{server_url}" if server_url.present?
      end

      def token_flag
        "--token #{token}" if token.present?
      end
    end
  end
end
