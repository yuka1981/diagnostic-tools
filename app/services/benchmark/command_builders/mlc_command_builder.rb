# frozen_string_literal: true

module Benchmark
  module CommandBuilders
    # Command builder for Intel MLC (Memory Latency Checker) benchmarks
    class MlcCommandBuilder < Base
      DEFAULT_PROFILE = "quick"

      def build
        command = base_command
        command = append_mlc_flags(command)
        append_common_flags(command)
      end

      protected

      def subcommand
        "mlc"
      end

      private

      def append_mlc_flags(command)
        flags = []
        flags << "--profile #{esc(profile)}"
        flags << "--binary #{esc(binary_path)}" if binary_path.present?
        flags.concat(modules_flags) if modules.present?
        flags << tests_flags if tests.present?
        flags << "--log-dir #{esc(arguments[:log_dir])}" if arguments[:log_dir].present?

        return command if flags.empty?

        "#{command} #{flags.join(' ')}"
      end

      def profile
        arguments[:profile].presence || DEFAULT_PROFILE
      end

      def binary_path
        arguments[:binary_path]
      end

      def modules
        arguments[:modules]
      end

      def tests
        arguments[:tests]
      end

      def modules_flags
        modules.map { |mod| "--module #{esc(mod)}" }
      end

      def tests_flags
        "--tests #{esc(tests.join(','))}"
      end
    end
  end
end
