# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: [ :mark_read ]

  def index
    @notifications = current_user.notifications.order(created_at: :desc)
    @notifications = @notifications.where(archived: false) unless params[:show_archived] == "true"
    @notifications = @notifications.by_status(params[:status]) if params[:status].present?
    @notifications = @notifications.by_type(params[:type]) if params[:type].present?
    @notifications = @notifications.page(params[:page]).per(20)

    @unread_count = current_user.notifications.unread.count
  end

  def mark_read
    NotificationService.mark_read(@notification)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@notification),
          turbo_stream.replace("notification_badge",
            partial: "notifications/badge",
            locals: { count: current_user.notifications.unread.count })
        ]
      end
      format.html { redirect_back(fallback_location: notifications_path) }
    end
  end

  def mark_all_read
    NotificationService.mark_all_read(current_user)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("notifications_list",
            partial: "notifications/list",
            locals: { notifications: current_user.notifications.for_dropdown }),
          turbo_stream.replace("notification_badge",
            partial: "notifications/badge",
            locals: { count: 0 })
        ]
      end
      format.html { redirect_to notifications_path, notice: "All notifications marked as read" }
    end
  end

  def archive_read
    NotificationService.archive_read(current_user)
    redirect_to notifications_path, notice: "Read notifications archived"
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end
end
