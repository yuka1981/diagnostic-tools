class AgentChannel < ApplicationCable::Channel
  periodically :beat, every: 1.minute

  def beat
    current_node.touch(:last_seen_at)
  end

  def subscribed
    stream_from "agent_#{current_node.uuid}"
    current_node.touch(:last_seen_at)
    Rails.logger.info "Node #{current_node.hostname} (#{current_node.uuid}) connected to AgentChannel"
  end

  def unsubscribed
    Rails.logger.info "Node #{current_node.hostname} (#{current_node.uuid}) disconnected from AgentChannel"
  end

  def receive(data)
    # Handle incoming data (e.g. command results)
    Rails.logger.info "Received data from #{current_node.hostname}: #{data}"

    if data["action"] == "report_result"
      if data["status"] == "success"
        payload = data["payload"]

        Inventory::ProcessStateService.new(
          node_id: current_node.id,
          raw_json: payload
        ).call
      else
        error_message = data["error"] || "Unknown error from agent"
        correlation_id = data["correlation_id"]
        Rails.logger.error "Agent on node #{current_node.hostname} reported an error (correlation_id: #{correlation_id}): #{error_message}"
      end
    end
  end
end
