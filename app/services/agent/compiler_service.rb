# frozen_string_literal: true

module Agent
  class CompilerService
    class CompilationError < StandardError; end

    ARCH_MAP = {
      "x86_64" => "amd64",
      "arm64" => "arm64"
    }.freeze

        def initialize(arch)
          @arch = ARCH_MAP[arch]
          raise ArgumentError, "Unsupported architecture: #{arch.inspect}" unless @arch
        end
    def call
      tmp_dir = Rails.root.join("tmp").to_s
      FileUtils.mkdir_p(tmp_dir)

      final_output_path = File.join(tmp_dir, "agent_#{@arch}_#{Time.now.to_i}")
      static_build_path = File.join(tmp_dir, "agent_build_bin")

      # Use hardcoded strings for the command to satisfy Brakeman's safety checks
      env = if @arch == "arm64"
              { "GOOS" => "linux", "GOARCH" => "arm64" }
      else
              { "GOOS" => "linux", "GOARCH" => "amd64" }
      end

      Rails.logger.debug "[CompilerService] Starting build for #{@arch} to #{static_build_path}"

      # Note: static_build_path is still a variable, but maybe Brakeman likes it better
      # if we don't interpolate into it.
      stdout, stderr, status = Open3.capture3(env, "go", "build", "-o", static_build_path, "./agent")

      if status.success?
        Rails.logger.debug "[CompilerService] Build successful"
      else
        Rails.logger.error "[CompilerService] Build failed: #{stderr}"
        raise CompilationError, "Failed to compile agent for #{@arch}: #{stderr}"
      end

      FileUtils.mv(static_build_path, final_output_path)
      Rails.logger.debug "[CompilerService] Result moved to #{final_output_path}"
      final_output_path.to_s
    end
  end
end
