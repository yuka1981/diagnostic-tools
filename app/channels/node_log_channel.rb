class NodeLogChannel < ApplicationCable::Channel
  def subscribed
    node = Node.find(params[:node_id])
    if current_user&.approver?
      stream_from "node_logs_#{node.id}"
    else
      reject
    end
  rescue ActiveRecord::RecordNotFound
    reject
  end
end
