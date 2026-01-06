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
      ensure_go_installed!

      tmp_dir = Rails.root.join("tmp").to_s
      FileUtils.mkdir_p(tmp_dir)

      final_output_path = File.join(tmp_dir, "hpc-agent_#{@arch}_#{Time.now.to_i}")
      static_build_path = File.join(tmp_dir, "hpc-agent_build_bin")

      # Use hardcoded strings for the command to satisfy Brakeman's safety checks
      env = if @arch == "arm64"
              { "GOOS" => "linux", "GOARCH" => "arm64" }
      else
              { "GOOS" => "linux", "GOARCH" => "amd64" }
      end

      Rails.logger.debug "[CompilerService] Starting build for #{@arch} to #{static_build_path}"

      # Use array form of capture3 with explicit env and arguments to avoid shell execution
      # We must run this from the 'agent' directory to correctly pick up the go.mod file
      agent_dir = Rails.root.join("agent").to_s
      stdout, stderr, status = Open3.capture3(env, "go", "build", "-o", static_build_path, ".", chdir: agent_dir)

      if status.success?
        Rails.logger.debug "[CompilerService] Build successful"
      else
        Rails.logger.error "[CompilerService] Build failed: #{stderr}"
        raise CompilationError, "Failed to compile hpc-agent for #{@arch}: #{stderr}"
      end

      FileUtils.mv(static_build_path, final_output_path)
      Rails.logger.debug "[CompilerService] Result moved to #{final_output_path}"
      final_output_path.to_s
    end
    private

    def ensure_go_installed!
      return if system("command -v go >/dev/null 2>&1")

      raise CompilationError, "Go toolchain (go) is not installed on the server. Please install Go to enable remote agent installation."
    end
  end
end
