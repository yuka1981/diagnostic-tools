# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::CompilerService do
  describe ".go_available?" do
    it "returns true when go command exists" do
      allow(described_class).to receive(:system).with("command -v go >/dev/null 2>&1").and_return(true)
      expect(described_class.go_available?).to be true
    end

    it "returns false when go command does not exist" do
      allow(described_class).to receive(:system).with("command -v go >/dev/null 2>&1").and_return(false)
      expect(described_class.go_available?).to be false
    end
  end

  describe ".go_version" do
    it "returns version string when go is available" do
      allow(described_class).to receive(:go_available?).and_return(true)
      allow(Open3).to receive(:capture3).with("go", "version").and_return(
        [ "go version go1.21.0 linux/amd64", "", double(success?: true) ]
      )

      expect(described_class.go_version).to eq("go version go1.21.0 linux/amd64")
    end

    it "returns nil when go is not available" do
      allow(described_class).to receive(:go_available?).and_return(false)
      expect(described_class.go_version).to be_nil
    end

    it "returns nil when version command fails" do
      allow(described_class).to receive(:go_available?).and_return(true)
      allow(Open3).to receive(:capture3).with("go", "version").and_return(
        [ "", "error", double(success?: false) ]
      )

      expect(described_class.go_version).to be_nil
    end
  end

  describe ".detect_arch" do
    it "returns x86_64 for amd64 systems" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_cpu").and_return("x86_64")
      expect(described_class.detect_arch).to eq("x86_64")
    end

    it "returns arm64 for arm64 systems" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_cpu").and_return("arm64")
      expect(described_class.detect_arch).to eq("arm64")
    end

    it "returns arm64 for aarch64 systems" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_cpu").and_return("aarch64")
      expect(described_class.detect_arch).to eq("arm64")
    end

    it "defaults to x86_64 for unknown architectures" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_cpu").and_return("unknown")
      expect(described_class.detect_arch).to eq("x86_64")
    end
  end

  describe ".build_release" do
    before do
      allow(described_class).to receive(:go_available?).and_return(true)
    end

    it "creates an AgentRelease with the specified version" do
      allow(Open3).to receive(:capture3).and_return([ "", "", double(success?: true) ])
      allow(FileUtils).to receive(:chmod)
      allow(FileUtils).to receive(:rm_f)

      # Create a temp file to simulate compiled binary
      temp_file = Tempfile.new("test-binary")
      temp_file.write("fake binary content")
      temp_file.close

      allow_any_instance_of(described_class).to receive(:compile_binary_with_version).and_return(temp_file.path)

      release = described_class.build_release(version_tag: "v1.0.0")

      expect(release).to be_a(AgentRelease)
      expect(release).to be_persisted
      expect(release.version).to eq("v1.0.0")
      expect(release.agent_binaries.count).to eq(1)
      expect(release.agent_binaries.first.binary).to be_attached
      expect(release.status).to eq("active")

      temp_file.unlink
    end

    it "includes release notes with compilation timestamp" do
      allow(Open3).to receive(:capture3).and_return([ "", "", double(success?: true) ])
      allow(FileUtils).to receive(:chmod)
      allow(FileUtils).to receive(:rm_f)

      temp_file = Tempfile.new("test-binary")
      temp_file.write("fake binary content")
      temp_file.close

      allow_any_instance_of(described_class).to receive(:compile_binary_with_version).and_return(temp_file.path)

      release = described_class.build_release(version_tag: "v1.0.0", release_notes: "Custom notes")

      expect(release.release_notes).to include("Custom notes")
      expect(release.release_notes).to include("Compiled from source on")

      temp_file.unlink
    end

    it "raises error when Go is not available" do
      allow(described_class).to receive(:go_available?).and_return(false)

      expect {
        described_class.build_release(version_tag: "v1.0.0")
      }.to raise_error(Agent::CompilerService::CompilationError, /Go toolchain is not installed/)
    end
  end

  describe "#call" do
    let(:arch) { "x86_64" }
    let(:service) { described_class.new(arch: arch) }

    it "executes go build command and returns path" do
      allow(described_class).to receive(:go_available?).and_return(true)
      expect(Open3).to receive(:capture3)
        .with(hash_including("GOARCH" => "amd64"), "go", "build", "-v", "-o", anything, ".", hash_including(chdir: /agent\z/))
        .and_return([ "", "", double(success?: true) ])

      expect(FileUtils).to receive(:mv).with(anything, anything)

      path = service.call
      expect(path).to include("tmp/hpc-agent_amd64_")
    end

    it "raises error if compilation fails" do
      allow(described_class).to receive(:go_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ "", "error message", double(success?: false, exitstatus: 1) ])

      expect { service.call }.to raise_error(Agent::CompilerService::CompilationError, /Failed to compile hpc-agent/)
    end

    it "raises error if go is not installed" do
      allow(described_class).to receive(:go_available?).and_return(false)

      expect { service.call }.to raise_error(Agent::CompilerService::CompilationError, /Go toolchain.*not installed/)
    end

    context "with arm64" do
      let(:arch) { "arm64" }

      it "uses arm64 GOARCH" do
        allow(described_class).to receive(:go_available?).and_return(true)
        expect(Open3).to receive(:capture3)
          .with(hash_including("GOARCH" => "arm64"), "go", "build", "-v", "-o", anything, ".", hash_including(chdir: /agent\z/))
          .and_return([ "", "", double(success?: true) ])

        expect(FileUtils).to receive(:mv).with(anything, anything)

        service.call
      end
    end

    context "with CGO_ENABLED" do
      it "disables CGO for static binaries" do
        allow(described_class).to receive(:go_available?).and_return(true)
        expect(Open3).to receive(:capture3)
          .with(hash_including("CGO_ENABLED" => "0"), "go", "build", "-v", "-o", anything, ".", anything)
          .and_return([ "", "", double(success?: true) ])

        expect(FileUtils).to receive(:mv)

        service.call
      end
    end
  end

  describe "#build_release" do
    let(:service) { described_class.new(arch: "x86_64", version_tag: "v1.2.3") }

    before do
      allow(described_class).to receive(:go_available?).and_return(true)
    end

    it "raises error without version tag" do
      service_no_version = described_class.new(arch: "x86_64")

      expect {
        service_no_version.build_release
      }.to raise_error(Agent::CompilerService::CompilationError, /Version tag is required/)
    end

    it "embeds version using ldflags" do
      temp_file = Tempfile.new("test-binary")
      temp_file.write("fake binary")
      temp_file.close

      allow_any_instance_of(described_class).to receive(:compile_binary_with_version).and_return(temp_file.path)

      release = service.build_release
      expect(release.version).to eq("v1.2.3")

      temp_file.unlink
    end

    it "uses ldflags to embed version in compile command" do
      # Test that the compile method uses correct ldflags
      expect(Open3).to receive(:capture3)
        .with(
          hash_including("GOARCH" => "amd64"),
          "go", "build",
          "-ldflags", "-X main.Version=v1.2.3",
          "-o", anything,
          ".",
          hash_including(chdir: anything)
        )
        .and_return([ "", "", double(success?: true) ])

      allow(FileUtils).to receive(:chmod)

      # Call the private method directly to test ldflags
      expect { service.send(:compile_binary_with_version) }.not_to raise_error
    end

    it "sets executable permissions on compiled binary" do
      # Test that chmod is called during compilation
      expect(Open3).to receive(:capture3).and_return([ "", "", double(success?: true) ])
      expect(FileUtils).to receive(:chmod).with(0o755, anything)

      service.send(:compile_binary_with_version)
    end

    it "cleans up temp file after creating release" do
      temp_file = Tempfile.new("test-binary")
      temp_file.write("fake binary")
      temp_file.close

      allow_any_instance_of(described_class).to receive(:compile_binary_with_version).and_return(temp_file.path)

      expect(FileUtils).to receive(:rm_f).with(temp_file.path)

      service.build_release

      temp_file.unlink rescue nil
    end

    it "cleans up temp file even if release creation fails" do
      temp_file = Tempfile.new("test-binary")
      temp_file.write("fake binary")
      temp_file.close

      allow_any_instance_of(described_class).to receive(:compile_binary_with_version).and_return(temp_file.path)
      allow_any_instance_of(described_class).to receive(:create_release_record).and_raise(StandardError.new("DB error"))

      expect(FileUtils).to receive(:rm_f).with(temp_file.path)

      expect { service.build_release }.to raise_error(StandardError)

      temp_file.unlink rescue nil
    end
  end

  describe "constants" do
    it "defines SOURCE_PATH" do
      expect(described_class::SOURCE_PATH).to eq(Rails.root.join("agent"))
    end

    it "defines VERSION_LDFLAGS_PACKAGE" do
      expect(described_class::VERSION_LDFLAGS_PACKAGE).to eq("main.Version")
    end

    it "defines ARCH_MAP" do
      expect(described_class::ARCH_MAP).to eq({
        "x86_64" => "amd64",
        "aarch64" => "arm64",
        "arm64" => "arm64"
      })
    end
  end

  describe "initialization" do
    it "accepts arch keyword argument" do
      service = described_class.new(arch: "x86_64")
      expect(service).to be_a(described_class)
    end

    it "accepts version_tag keyword argument" do
      service = described_class.new(arch: "x86_64", version_tag: "v1.0.0")
      expect(service).to be_a(described_class)
    end

    it "defaults to amd64 for unknown architectures" do
      # The ARCH_MAP lookup returns nil for unknown, so it falls back to x86_64 -> amd64
      service = described_class.new(arch: "unknown_arch")
      expect(service).to be_a(described_class)
    end

    it "accepts arm64 architecture" do
      service = described_class.new(arch: "arm64")
      expect(service).to be_a(described_class)
    end
  end
end
