# frozen_string_literal: true

require "open3"

module Agent
  class CompilerService
    class CompilationError < StandardError; end

    ARCH_MAP = {
      "x86_64" => "amd64",
      "aarch64" => "arm64",
      "arm64" => "arm64"
    }.freeze

    # Map Go arch back to our standard arch names for AgentBinary
    ARCH_STANDARD = {
      "amd64" => "x86_64",
      "arm64" => "aarch64"
    }.freeze

    SOURCE_PATH = Rails.root.join("agent")
    VERSION_LDFLAGS_PACKAGE = "main.Version"

    # Safe patterns for user-provided inputs to prevent command injection
    VERSION_TAG_PATTERN = /\A[a-zA-Z0-9._-]+\z/
    LDFLAGS_SAFE_PATTERN = /\A[a-zA-Z0-9._=\s\/-]+\z/

    # Build and create an AgentRelease record from source
    # @param version_tag [String] Version string (e.g., "v1.0.0")
    # @param release_notes [String, nil] Optional release notes
    # @param arch [String] Target architecture (default: auto-detect)
    # @param custom_ldflags [String, nil] Additional ldflags for compilation
    # @return [AgentRelease] The created release record
    def self.build_release(version_tag:, release_notes: nil, arch: nil, custom_ldflags: nil)
      target_arch = arch.presence || detect_arch
      new(arch: target_arch, version_tag: version_tag, custom_ldflags: custom_ldflags)
        .build_release(release_notes: release_notes)
    end

    # Check if Go toolchain is available
    def self.go_available?
      system("command -v go >/dev/null 2>&1")
    end

    # Get Go version string
    def self.go_version
      return nil unless go_available?

      stdout, _stderr, status = Open3.capture3("go", "version")
      return nil unless status.success?

      stdout.strip
    end

    # Detect current system architecture
    def self.detect_arch
      arch = RbConfig::CONFIG["host_cpu"]
      case arch
      when /x86_64|amd64/
        "x86_64"
      when /arm64|aarch64/
        "arm64"
      else
        "x86_64" # Default to x86_64
      end
    end

    def initialize(arch:, version_tag: nil, custom_ldflags: nil)
      @arch = ARCH_MAP[arch] || ARCH_MAP["x86_64"]
      @version_tag = version_tag
      @custom_ldflags = custom_ldflags
      raise ArgumentError, "Unsupported architecture: #{arch.inspect}" unless @arch
    end

    # Compile and return path to binary (original behavior for remote install)
    def call
      ensure_go_installed!
      compile_binary
    end

    # Compile and create an AgentRelease record
    # @param release_notes [String, nil] Optional release notes
    # @return [AgentRelease] The created release record
    def build_release(release_notes: nil)
      ensure_go_installed!
      validate_version_tag!
      validate_custom_ldflags!

      output_path = compile_binary_with_version

      begin
        agent_release = create_release_record(output_path, release_notes)
        agent_release
      ensure
        # Cleanup temp file
        FileUtils.rm_f(output_path) if File.exist?(output_path)
      end
    end

    private

    def validate_version_tag!
      raise CompilationError, "Version tag is required for building a release" if @version_tag.blank?
      unless VERSION_TAG_PATTERN.match?(@version_tag)
        raise CompilationError, "Invalid version tag format. Only alphanumeric characters, dots, dashes, and underscores are allowed."
      end
    end

    def validate_custom_ldflags!
      return if @custom_ldflags.blank?
      unless LDFLAGS_SAFE_PATTERN.match?(@custom_ldflags)
        raise CompilationError, "Invalid custom ldflags format. Only alphanumeric characters, dots, dashes, underscores, equals signs, slashes, and spaces are allowed."
      end
    end

    def compile_binary
      tmp_dir = Rails.root.join("tmp").to_s
      FileUtils.mkdir_p(tmp_dir)

      final_output_path = File.join(tmp_dir, "hpc-agent_#{@arch}_#{Time.now.to_i}")
      static_build_path = File.join(tmp_dir, "hpc-agent_build_bin")

      env = build_environment

      Rails.logger.debug "[CompilerService] Starting build for #{@arch} to #{static_build_path}"
      Rails.logger.debug "[CompilerService] Working directory: #{SOURCE_PATH}"
      Rails.logger.debug "[CompilerService] Environment: #{env.inspect}"

      stdout, stderr, status = Open3.capture3(
        env, "go", "build", "-v", "-o", static_build_path, ".",
        chdir: SOURCE_PATH.to_s
      )

      unless status.success?
        Rails.logger.error "[CompilerService] Build failed with status #{status.exitstatus}"
        Rails.logger.error "[CompilerService] Stderr: #{stderr}"
        raise CompilationError, "Failed to compile hpc-agent for #{@arch}: #{stderr}"
      end

      Rails.logger.debug "[CompilerService] Build successful"
      FileUtils.mv(static_build_path, final_output_path)
      Rails.logger.debug "[CompilerService] Result moved to #{final_output_path}"

      final_output_path.to_s
    end

    def compile_binary_with_version
      tmp_dir = Rails.root.join("tmp").to_s
      FileUtils.mkdir_p(tmp_dir)

      random_id = SecureRandom.hex(8)
      output_path = File.join(tmp_dir, "diagnostic-agent-#{random_id}")

      env = build_environment
      ldflags = build_ldflags

      Rails.logger.info "[CompilerService] Building release #{@version_tag} for #{@arch}"
      Rails.logger.debug "[CompilerService] Output path: #{output_path}"
      Rails.logger.debug "[CompilerService] ldflags: #{ldflags}"

      stdout, stderr, status = Open3.capture3(
        env,
        "go", "build",
        "-ldflags", ldflags,
        "-o", output_path,
        ".",
        chdir: SOURCE_PATH.to_s
      )

      unless status.success?
        Rails.logger.error "[CompilerService] Build failed with status #{status.exitstatus}"
        Rails.logger.error "[CompilerService] Stdout: #{stdout}"
        Rails.logger.error "[CompilerService] Stderr: #{stderr}"
        raise CompilationError, "Compilation failed: #{stderr.presence || stdout}"
      end

      # Ensure binary is executable
      FileUtils.chmod(0o755, output_path)

      Rails.logger.info "[CompilerService] Build successful: #{output_path}"
      output_path
    end

    def build_ldflags
      flags = [ "-X #{VERSION_LDFLAGS_PACKAGE}=#{@version_tag}" ]
      flags << @custom_ldflags if @custom_ldflags.present?
      flags.join(" ")
    end

    def create_release_record(binary_path, release_notes)
      # Find existing release or create new one
      agent_release = AgentRelease.find_by(version: @version_tag)
      standard_arch = ARCH_STANDARD[@arch] || "x86_64"

      if agent_release
        # Adding binary to existing release
        Rails.logger.info "[CompilerService] Adding #{standard_arch} binary to existing release #{@version_tag}"

        if agent_release.has_binary_for_arch?(standard_arch)
          raise CompilationError, "Release #{@version_tag} already has a binary for #{standard_arch}"
        end
      else
        # Create new release
        compiled_time = Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")
        default_notes = "Compiled from source on #{compiled_time}"

        full_notes = if release_notes.present?
                       "#{release_notes}\n\n---\n_#{default_notes}_"
        else
                       default_notes
        end

        agent_release = AgentRelease.new(
          version: @version_tag,
          release_notes: full_notes,
          status: :active
        )

        unless agent_release.save
          raise CompilationError, "Failed to save release: #{agent_release.errors.full_messages.join(', ')}"
        end

        Rails.logger.info "[CompilerService] Created new release #{@version_tag}"
      end

      # Create AgentBinary for this architecture
      agent_binary = agent_release.agent_binaries.build(arch: standard_arch)
      agent_binary.binary.attach(
        io: File.open(binary_path, "rb"),
        filename: "hpc-agent-#{@version_tag}-linux-#{standard_arch}",
        content_type: "application/octet-stream"
      )

      unless agent_binary.save
        raise CompilationError, "Failed to save binary: #{agent_binary.errors.full_messages.join(', ')}"
      end

      Rails.logger.info "[CompilerService] Created AgentBinary for #{standard_arch}"
      agent_release
    end

    def build_environment
      if @arch == "arm64"
        { "GOOS" => "linux", "GOARCH" => "arm64", "CGO_ENABLED" => "0" }
      else
        { "GOOS" => "linux", "GOARCH" => "amd64", "CGO_ENABLED" => "0" }
      end
    end

    def ensure_go_installed!
      return if self.class.go_available?

      raise CompilationError, "Go toolchain is not installed on the server. Please install Go to enable agent compilation."
    end
  end
end
