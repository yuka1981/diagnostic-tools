module Mlc
  class BinaryDetectionService
    Result = Struct.new(:success?, :candidates, :error, keyword_init: true)
    Candidate = Struct.new(:path, :relative_path, :size, :file_type, keyword_init: true)

    VERSION_REGEX = /v?(\d+\.\d+(?:\.\d+)?)/

    def initialize(extract_dir)
      @extract_dir = extract_dir
    end

    def call
      candidates = find_binary_candidates
      if candidates.empty?
        Result.new(success?: false, error: "No MLC binary detected in extracted contents")
      else
        Result.new(success?: true, candidates: candidates)
      end
    end

    def detect_version(binary_path)
      return nil unless File.executable?(binary_path)

      output = `#{Shellwords.escape(binary_path)} --version 2>&1`.strip
      match = output.match(VERSION_REGEX)
      match ? match[1] : nil
    rescue StandardError
      nil
    end

    private

    def find_binary_candidates
      candidates = []

      Dir.glob(File.join(@extract_dir, "**", "*")).each do |path|
        next unless File.file?(path)
        next unless File.basename(path).downcase.include?("mlc")

        file_type = detect_file_type(path)
        next unless binary_file_type?(file_type)

        relative = path.sub("#{@extract_dir}/", "")
        candidates << Candidate.new(
          path: path,
          relative_path: relative,
          size: File.size(path),
          file_type: file_type
        )
      end

      candidates
    end

    def detect_file_type(path)
      `file -b #{Shellwords.escape(path)}`.strip
    rescue StandardError
      "unknown"
    end

    def binary_file_type?(file_type)
      file_type.match?(/ELF|PE32|Mach-O|executable/i)
    end
  end
end
