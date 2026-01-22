# frozen_string_literal: true

module Api
  class NodesController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_forgery_protection

    # GET /api/nodes/hostname_suggestions
    # Returns hostname suggestions based on prefix or bulk pattern
    #
    # For single prefix (e.g., "compute"):
    #   { existing: [...], suggestions: [...] }
    #
    # For bulk pattern (e.g., "compute-[001-005]"):
    #   { bulk: true, hostnames: [...], conflicts: [...], available: [...] }
    def hostname_suggestions
      prefix = params[:prefix].to_s.strip

      if prefix.blank?
        render json: { existing: [], suggestions: [] }
        return
      end

      if bulk_pattern?(prefix)
        render json: bulk_suggestions(prefix)
      else
        render json: single_suggestions(prefix)
      end
    end

    private

    # Maximum number of hostnames to expand from a bulk pattern
    MAX_BULK_EXPANSION = 100

    # Maximum number of suggestions to return for gap filling
    MAX_SUGGESTIONS = 10

    # Checks if the prefix contains a bulk range pattern like [001-005]
    def bulk_pattern?(prefix)
      prefix.match?(/\[\d+-\d+\]/)
    end

    # Expands a bulk pattern and finds conflicts with existing hostnames
    def bulk_suggestions(prefix)
      hostnames = expand_bulk_pattern(prefix)
      existing_hostnames = Node.where(hostname: hostnames).pluck(:hostname)
      conflicts = hostnames & existing_hostnames
      available = hostnames - existing_hostnames

      {
        bulk: true,
        hostnames: hostnames,
        conflicts: conflicts,
        available: available
      }
    end

    # Expands a pattern like "compute-[001-005]" into an array of hostnames
    def expand_bulk_pattern(prefix)
      match = prefix.match(/\[(\d+)-(\d+)\]/)
      return [] unless match

      start_num = match[1].to_i
      end_num = match[2].to_i
      padding = match[1].length

      return [] if start_num > end_num

      base_prefix = prefix.sub(/\[\d+-\d+\]/, "")
      count = [ end_num - start_num + 1, MAX_BULK_EXPANSION ].min

      (start_num...(start_num + count)).map do |n|
        "#{base_prefix}#{n.to_s.rjust(padding, '0')}"
      end
    end

    # Returns existing matches and suggestions for next available hostnames
    def single_suggestions(prefix)
      sanitized_prefix = sanitize_like(prefix)
      existing = Node.where("hostname LIKE ?", "#{sanitized_prefix}%")
                     .order(:hostname)
                     .limit(20)
                     .pluck(:hostname)

      suggestions = calculate_suggestions(prefix, existing)

      {
        existing: existing,
        suggestions: suggestions
      }
    end

    # Calculates suggested hostnames by finding gaps in numbering
    # and suggesting the next available hostname
    def calculate_suggestions(prefix, existing)
      return [] if existing.empty?

      # Extract numbers from existing hostnames that match the pattern
      # e.g., for prefix "compute-" and hostnames ["compute-001", "compute-002", "compute-005"]
      # we want to find [1, 2, 5]
      numbers_with_format = extract_numbers_with_format(prefix, existing)
      return [] if numbers_with_format.empty?

      numbers = numbers_with_format.map { |h| h[:number] }.sort
      padding = numbers_with_format.first[:padding]
      base_prefix = numbers_with_format.first[:base_prefix]

      suggestions = []

      # Find gaps in the sequence
      (numbers.min..numbers.max).each do |n|
        break if suggestions.size >= MAX_SUGGESTIONS

        suggestions << format_hostname(base_prefix, n, padding) unless numbers.include?(n)
      end

      # Add next available numbers after the max
      next_num = numbers.max + 1
      while suggestions.size < MAX_SUGGESTIONS
        suggestions << format_hostname(base_prefix, next_num, padding)
        next_num += 1
      end

      suggestions
    end

    # Extracts numbers and their formatting from hostnames matching a prefix
    def extract_numbers_with_format(prefix, hostnames)
      # Match hostnames like "compute-001", "node001", "gpu-a-01"
      # Try to find the numeric suffix pattern
      results = []

      hostnames.each do |hostname|
        next unless hostname.start_with?(prefix) || hostname.match?(/^#{Regexp.escape(prefix)}/)

        # Find trailing number in hostname
        match = hostname.match(/^(.+?)(\d+)$/)
        next unless match

        base = match[1]
        num_str = match[2]

        results << {
          hostname: hostname,
          base_prefix: base,
          number: num_str.to_i,
          padding: num_str.length
        }
      end

      results
    end

    # Formats a hostname with the given prefix, number, and padding
    def format_hostname(base_prefix, number, padding)
      "#{base_prefix}#{number.to_s.rjust(padding, '0')}"
    end

    # Escapes SQL LIKE wildcards in a string
    def sanitize_like(str)
      str.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end
  end
end
