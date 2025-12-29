# frozen_string_literal: true

module Nodes
  class ImportsController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!

    def new
      # Render the import modal form
    end

    def create
      unless params[:file].present?
        return render_error("Please select a CSV file to import")
      end

      csv_content = params[:file].read
      result = Inventory::ImportCsvService.new(csv_content).call

      if result.success?
        handle_success(result)
      else
        handle_failure(result)
      end
    end

    private

    def handle_success(result)
      message = build_success_message(result)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("import_modal", ""),
            turbo_stream.update("flash_messages", partial: "shared/flash", locals: { notice: message }),
            turbo_stream.replace("nodes_table", partial: "nodes/table", locals: { nodes: Node.order(:hostname) })
          ]
        end
        format.html { redirect_to nodes_path, notice: message }
      end
    end

    def handle_failure(result)
      error_message = build_error_message(result)
      render_error(error_message)
    end

    def render_error(message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("import_errors", partial: "nodes/imports/errors", locals: { message: message }),
                 status: :unprocessable_content
        end
        format.html do
          flash.now[:alert] = message
          render :new, status: :unprocessable_content
        end
      end
    end

    def build_success_message(result)
      parts = []
      parts << "#{result.created_count} created" if result.created_count > 0
      parts << "#{result.updated_count} updated" if result.updated_count > 0
      parts << "#{result.error_count} errors" if result.error_count > 0

      "Import complete: #{parts.join(', ')}"
    end

    def build_error_message(result)
      errors = result.errors.map do |error|
        if error[:row]
          "Row #{error[:row]}: #{error[:message]}"
        else
          error[:message]
        end
      end
      errors.join("; ")
    end
  end
end
