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

    def initialize(csv_content)
      @csv_content = csv_content
      @created_count = 0
      @updated_count = 0
      @errors = []
    end

    def call
      return error_result("CSV content is empty") if @csv_content.blank?

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
      error_result("Malformed CSV: #{e.message}")
    end

    def process_rows(csv)
      return error_result("Missing required header: hostname") unless valid_headers?(csv.headers)

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

      # Check for validation errors added during assign_attributes
      if node.errors.any?
        @errors << { row: row_number, message: node.errors.full_messages.join(", ") }
        return
      end

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

      # Only set role if provided
      role_value = row["role"]&.strip
      if role_value.present?
        role = role_value.downcase
        if Node.roles.key?(role)
          node.role = role
        else
          node.errors.add(:role, "'#{role_value}' is not a valid role")
        end
      end
    end

    def error_result(message, row: nil)
      Result.new(
        success: false,
        created_count: 0,
        updated_count: 0,
        error_count: 1,
        errors: [ { row: row, message: message } ]
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
