module Api
  module V1
    class MlcInstallationsController < BaseController
      before_action :set_installation
      before_action :set_installation_node

      def progress
        @installation_node.update!(
          step_current: params[:step],
          step_total: params[:total_steps],
          step_name: params[:step_name]
        )

        broadcast_progress_update

        render json: { status: "ok" }
      end

      def complete
        if params[:status] == "success"
          handle_success
        else
          handle_failure
        end

        check_installation_complete

        render json: { status: "ok" }
      end

      private

      def set_installation
        @installation = MlcInstallation.find_by!(uuid: params[:uuid])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Installation not found" }, status: :not_found
      end

      def set_installation_node
        return if @installation.nil?

        node = Node.find_by!(uuid: params[:node_id])
        @installation_node = @installation.mlc_installation_nodes.find_by!(node: node)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Node not found in this installation" }, status: :not_found
      end

      def handle_success
        @installation_node.update!(
          status: :success,
          completed_at: Time.current,
          step_current: @installation_node.step_total
        )

        if params[:detected_version].present? && @installation.detected_version.blank?
          @installation.update!(detected_version: params[:detected_version])
        end
      end

      def handle_failure
        @installation_node.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: params[:error_message],
          step_current: params[:failed_at_step],
          step_name: params[:failed_step_name]
        )
      end

      def check_installation_complete
        return unless @installation.mlc_installation_nodes.pending.empty? &&
                      @installation.mlc_installation_nodes.running.empty?

        if @installation.mlc_installation_nodes.failed.any?
          @installation.update!(status: :failed, completed_at: Time.current)
        else
          @installation.update!(status: :completed, completed_at: Time.current)
        end

        broadcast_installation_complete
      end

      def broadcast_progress_update
        return unless defined?(Turbo::StreamsChannel)

        @installation_node.broadcast_replace_to(
          "mlc_installation_#{@installation.id}",
          target: "mlc_installation_node_#{@installation_node.id}",
          partial: "mlc_installations/node_status",
          locals: { installation_node: @installation_node }
        )
      rescue StandardError
        # Ignore broadcast errors
      end

      def broadcast_installation_complete
        return unless defined?(Turbo::StreamsChannel)

        @installation.broadcast_replace_to(
          "mlc_installation_#{@installation.id}",
          target: "mlc_installation_status",
          partial: "mlc_installations/status",
          locals: { installation: @installation }
        )
      rescue StandardError
        # Ignore broadcast errors
      end
    end
  end
end
