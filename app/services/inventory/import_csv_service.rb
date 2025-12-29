# frozen_string_literal: true

require "csv"

module Inventory
  class ImportCsvService
    Result = Struct.new(:success, :created_count, :updated_count, :error_count, :errors, keyword_init: true) do
      def success?
        success
      end
    end

    REQUIRED_HEADERS = %w[hostname].freeze
    VALID_HEADERS = %w[hostname ip role arch].freeze

    def initialize(csv_content)
      @csv_content = csv_content
      @created_count = 0
      @updated_count = 0
      @errors = []
    end

    def call
      return empty_csv_error if @csv_content.blank?

      parsed = parse_csv
      return parsed if parsed.is_a?(Result)

      header_result = process_rows(parsed)
      return header_result if header_result.is_a?(Result)

      build_result
    end

    private

    def parse_csv
      CSV.parse(@csv_content, headers: true, header_converters: :downcase, skip_blanks: true)
    rescue CSV::MalformedCSVError => e
      Result.new(
        success: false,
        created_count: 0,
        updated_count: 0,
        error_count: 1,
        errors: [ { row: nil, message: "Malformed CSV: #{e.message}" } ]
      )
    end

    def process_rows(csv)
      unless valid_headers?(csv.headers)
        return Result.new(
          success: false,
          created_count: 0,
          updated_count: 0,
          error_count: 1,
          errors: [ { row: nil, message: "Missing required header: hostname" } ]
        )
      end

      csv.each.with_index(2) do |row, row_number|
        process_row(row, row_number)
      end
    end

    def valid_headers?(headers)
      return false if headers.nil?

      REQUIRED_HEADERS.all? { |h| headers.include?(h) }
    end

    def process_row(row, row_number)
      hostname = row["hostname"]&.strip

      if hostname.blank?
        @errors << { row: row_number, message: "Hostname is required" }
        return
      end

      node = Node.find_or_initialize_by(hostname: hostname)
      is_new = node.new_record?

      assign_attributes(node, row)

      if node.save
        is_new ? @created_count += 1 : @updated_count += 1
      else
        @errors << { row: row_number, message: node.errors.full_messages.join(", ") }
      end
    end

    def assign_attributes(node, row)
      node.ip = row["ip"]&.strip.presence
      node.arch = row["arch"]&.strip.presence
      node.source = :csv

      # Only set role if provided and valid
      role = row["role"]&.strip&.downcase
      if role.present? && Node.roles.key?(role)
        node.role = role
      elsif role.present?
        # Invalid role - let validation catch it
        node.role = nil
      end
    end

    def empty_csv_error
      Result.new(
        success: false,
        created_count: 0,
        updated_count: 0,
        error_count: 1,
        errors: [ { row: nil, message: "CSV content is empty" } ]
      )
    end

    def build_result
      Result.new(
        success: @errors.empty?,
        created_count: @created_count,
        updated_count: @updated_count,
        error_count: @errors.size,
        errors: @errors
      )
    end
  end
end
