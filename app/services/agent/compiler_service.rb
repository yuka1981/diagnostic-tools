# frozen_string_literal: true

module Agent
  class CompilerService
    class CompilationError < StandardError; end

    ARCH_MAP = {
      "x86_64" => "amd64",
      "arm64" => "arm64"
    }.freeze

    def initialize(arch)
      @arch = ARCH_MAP[arch] || arch
    end

    def call
      output_path = Rails.root.join("tmp", "agent_#{@arch}_#{Time.now.to_i}")

      # Ensure tmp exists
      FileUtils.mkdir_p(Rails.root.join("tmp"))

      cmd = "GOOS=linux GOARCH=#{@arch} go build -o #{output_path} ./agent"

      Rails.logger.info "Compiling agent for #{@arch}: #{cmd}"

      stdout, stderr, status = Open3.capture3(cmd)

      unless status.success?
        Rails.logger.error "Agent compilation failed: #{stderr}"
        raise CompilationError, "Failed to compile agent for #{@arch}: #{stderr}"
      end

      output_path.to_s
    end
  end
end
