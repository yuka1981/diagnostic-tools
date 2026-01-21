# frozen_string_literal: true

class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    if current_user
      stream_from "notifications_user_#{current_user.id}"
      Rails.logger.debug "[NotificationsChannel] User #{current_user.id} subscribed"
    else
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end
end
