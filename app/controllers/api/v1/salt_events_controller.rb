# frozen_string_literal: true

module Api
  module V1
    class SaltEventsController < BaseController
      def create
        body = JSON.parse(request.body.read)
        tag = body["tag"]

        if tag.blank?
          render json: { error: "Missing required field: tag" }, status: :unprocessable_entity
          return
        end

        Salt::EventListenerService.new.dispatch_event(tag, body)

        render json: { success: true }
      rescue JSON::ParserError => e
        render json: { error: "Invalid JSON: #{e.message}" }, status: :bad_request
      end
    end
  end
end
