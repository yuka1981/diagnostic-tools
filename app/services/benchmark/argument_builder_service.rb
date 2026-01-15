# frozen_string_literal: true

module Benchmark
  # Service to merge recipe defaults with user overrides and build CLI argument string
  #
  # @example
  #   service = ArgumentBuilderService.new(
  #     defaults: { "nx" => 104, "ny" => 104 },
  #     overrides: { "nx" => 128 }
  #   )
  #   service.call # => "--nx=128 --ny=104"
  #   service.merged_arguments # => { "nx" => 128, "ny" => 104 }
  #
  class ArgumentBuilderService
    # @param defaults [Hash] Default arguments from recipe
    # @param overrides [Hash] User-provided override values
    def initialize(defaults:, overrides:)
      @defaults = normalize_hash(defaults || {})
      @overrides = normalize_hash(overrides || {})
    end

    # Build CLI flags string from merged arguments
    # @return [String] CLI flags string (e.g., "--nx=128 --ny=104")
    def call
      build_cli_flags(merged_arguments)
    end

    # Get the merged arguments hash (for audit/snapshot purposes)
    # @return [Hash] Merged arguments with overrides taking precedence
    def merged_arguments
      # Start with defaults, merge overrides (overrides win)
      merged = @defaults.merge(@overrides)

      # Remove any keys that were explicitly set to nil in overrides
      @overrides.each do |key, value|
        merged.delete(key) if value.nil?
      end

      merged
    end

    private

    # Normalize hash keys to strings and deep stringify
    def normalize_hash(hash)
      return {} unless hash.is_a?(Hash)

      hash.transform_keys(&:to_s)
    end

    # Build CLI flags string from arguments hash
    # @param args [Hash] Arguments to convert to CLI flags
    # @return [String] CLI flags string
    def build_cli_flags(args)
      flags = args.filter_map do |key, value|
        build_single_flag(key, value)
      end

      flags.join(" ")
    end

    # Build a single CLI flag
    # @param key [String] Argument name
    # @param value [Object] Argument value
    # @return [String, nil] CLI flag string or nil if value should be skipped
    def build_single_flag(key, value)
      # Skip nil values
      return nil if value.nil?

      # Skip array values (not supported as CLI flags)
      return nil if value.is_a?(Array)

      # Skip hash values (not supported as CLI flags)
      return nil if value.is_a?(Hash)

      # Convert key: underscores to hyphens for CLI convention
      flag_name = key.to_s.tr("_", "-")

      # Handle boolean values
      if value == true
        "--#{flag_name}"
      elsif value == false
        nil # Don't include false boolean flags
      else
        # Escape value if it contains spaces or special characters
        escaped_value = escape_value(value.to_s)
        "--#{flag_name}=#{escaped_value}"
      end
    end

    # Escape a value for shell safety
    # @param value [String] Value to escape
    # @return [String] Escaped value
    def escape_value(value)
      # If value contains spaces or special characters, quote it
      if value.match?(/[\s'"\\]/)
        Shellwords.escape(value)
      else
        value
      end
    end
  end
end
