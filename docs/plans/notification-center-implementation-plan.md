# Notification Center Implementation Plan

**Date:** 2026-01-21
**Design Document:** [2026-01-21-notification-center-design.md](./2026-01-21-notification-center-design.md)
**Status:** Ready for Implementation

## Overview

This plan implements a notification center for tracking long-running background tasks with real-time updates via ActionCable. Users can view task progress, see completion badges, and navigate to related resources.

---

## Phase 1: Database & Model

### Step 1.1: Create Notifications Migration

**Files to create:**
- `db/migrate/XXXXXX_create_notifications.rb`

**Implementation details:**
```ruby
class CreateNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :notification_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :title, null: false
      t.string :message
      t.string :resource_type
      t.bigint :resource_id
      t.jsonb :metadata, default: {}
      t.boolean :read, default: false
      t.boolean :archived, default: false
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :notifications, [:user_id, :archived, :read]
    add_index :notifications, [:user_id, :created_at]
    add_index :notifications, [:resource_type, :resource_id]
  end
end
```

**Verification:**
```bash
bin/rails db:migrate
bin/rails db:rollback && bin/rails db:migrate  # Test reversibility
```

---

### Step 1.2: Create Notification Model

**Files to create:**
- `app/models/notification.rb`
- `spec/models/notification_spec.rb`
- `spec/factories/notifications.rb`

**Implementation details:**

`app/models/notification.rb`:
```ruby
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :resource, polymorphic: true, optional: true

  # Notification types
  TYPES = %w[agent_install agent_update agent_uninstall benchmark inventory_collect product_sync].freeze

  # Status enum
  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed" }

  # Validations
  validates :notification_type, presence: true, inclusion: { in: TYPES }
  validates :title, presence: true
  validates :status, presence: true

  # Scopes
  scope :unread, -> { where(read: false, archived: false) }
  scope :active, -> { where(archived: false) }
  scope :for_dropdown, -> { active.order(created_at: :desc).limit(10) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(notification_type: type) if type.present? }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  # Helper methods
  def progress_percent
    metadata["progress_percent"]
  end

  def in_progress?
    pending? || running?
  end

  def terminal?
    completed? || failed?
  end
end
```

**Verification:**
```bash
bin/rspec spec/models/notification_spec.rb
bin/rails console
# Test: Notification.new(user: User.first, notification_type: "agent_install", title: "Test").valid?
```

---

### Step 1.3: Add User Association

**Files to modify:**
- `app/models/user.rb`

**Implementation details:**

Add to `app/models/user.rb`:
```ruby
has_many :notifications, dependent: :destroy
```

**Verification:**
```bash
bin/rails console
# Test: User.first.notifications
```

---

## Phase 2: Service Layer

### Step 2.1: Create NotificationService

**Files to create:**
- `app/services/notification_service.rb`
- `spec/services/notification_service_spec.rb`

**Implementation details:**

`app/services/notification_service.rb`:
```ruby
class NotificationService
  include ActionView::RecordIdentifier

  class << self
    # Create a new notification and broadcast to user
    def create(user:, type:, title:, resource: nil, metadata: {})
      notification = Notification.create!(
        user: user,
        notification_type: type,
        status: "pending",
        title: title,
        resource_type: resource&.class&.name,
        resource_id: resource&.id,
        metadata: metadata
      )
      broadcast_notification(notification)
      notification
    end

    # Mark as running with optional progress
    def start(notification, progress: nil)
      notification.update!(status: "running", started_at: Time.current)
      notification.metadata["progress_percent"] = progress if progress
      notification.save! if progress
      broadcast_notification(notification)
    end

    # Update progress during execution
    def progress(notification, percent:, message: nil)
      notification.metadata["progress_percent"] = percent
      notification.message = message if message
      notification.save!
      broadcast_notification(notification)
    end

    # Mark completed (success or failure)
    def complete(notification, success:, message: nil, metadata: {})
      notification.update!(
        status: success ? "completed" : "failed",
        message: message,
        metadata: notification.metadata.merge(metadata),
        completed_at: Time.current
      )
      broadcast_notification(notification)
      broadcast_badge_update(notification.user)
    end

    # Mark single notification as read
    def mark_read(notification)
      notification.update!(read: true)
      broadcast_notification(notification)
      broadcast_badge_update(notification.user)
    end

    # Mark all unread notifications as read for a user
    def mark_all_read(user)
      user.notifications.unread.update_all(read: true, updated_at: Time.current)
      broadcast_list_update(user)
      broadcast_badge_update(user)
    end

    # Archive read notifications for a user
    def archive_read(user)
      user.notifications.where(read: true, archived: false).update_all(archived: true, updated_at: Time.current)
    end

    private

    def broadcast_notification(notification)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(notification.user),
        target: dom_id(notification),
        partial: "notifications/notification",
        locals: { notification: notification }
      )
    end

    def broadcast_badge_update(user)
      count = user.notifications.unread.count
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(user),
        target: "notification_badge",
        partial: "notifications/badge",
        locals: { count: count }
      )
    end

    def broadcast_list_update(user)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(user),
        target: "notifications_list",
        partial: "notifications/list",
        locals: { notifications: user.notifications.for_dropdown }
      )
    end

    def stream_name(user)
      "notifications_user_#{user.id}"
    end
  end
end
```

**Verification:**
```bash
bin/rspec spec/services/notification_service_spec.rb
bin/rails console
# Test: NotificationService.create(user: User.first, type: "agent_install", title: "Test Install")
```

---

## Phase 3: ActionCable

### Step 3.1: Create NotificationsChannel

**Files to create:**
- `app/channels/notifications_channel.rb`
- `spec/channels/notifications_channel_spec.rb`

**Implementation details:**

`app/channels/notifications_channel.rb`:
```ruby
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
```

**Verification:**
```bash
bin/rspec spec/channels/notifications_channel_spec.rb
# Manual test: Open browser console, check ActionCable subscription
```

---

## Phase 4: Controller & Routes

### Step 4.1: Create NotificationsController

**Files to create:**
- `app/controllers/notifications_controller.rb`
- `spec/controllers/notifications_controller_spec.rb` (or `spec/requests/notifications_spec.rb`)

**Implementation details:**

`app/controllers/notifications_controller.rb`:
```ruby
class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: [:mark_read]

  def index
    @notifications = current_user.notifications
                                  .order(created_at: :desc)
                                  .page(params[:page])
                                  .per(20)

    @notifications = @notifications.where(archived: false) unless params[:show_archived] == "true"
    @notifications = @notifications.by_status(params[:status])
    @notifications = @notifications.by_type(params[:type])

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
```

**Verification:**
```bash
bin/rspec spec/requests/notifications_spec.rb
```

---

### Step 4.2: Add Routes

**Files to modify:**
- `config/routes.rb`

**Implementation details:**

Add to `config/routes.rb`:
```ruby
resources :notifications, only: [:index] do
  member do
    post :mark_read
  end
  collection do
    post :mark_all_read
    post :archive_read
  end
end
```

**Verification:**
```bash
bin/rails routes | grep notification
# Should show:
#   mark_read_notification POST /notifications/:id/mark_read
#   mark_all_read_notifications POST /notifications/mark_all_read
#   archive_read_notifications POST /notifications/archive_read
#   notifications GET /notifications
```

---

## Phase 5: Navbar UI

### Step 5.1: Create Badge Partial

**Files to create:**
- `app/views/notifications/_badge.html.erb`

**Implementation details:**

`app/views/notifications/_badge.html.erb`:
```erb
<% count ||= 0 %>
<% if count > 0 %>
  <span id="notification_badge"
        class="absolute -top-1 -right-1 bg-red-500 text-white text-xs
               rounded-full h-5 w-5 flex items-center justify-center font-medium">
    <%= count > 9 ? "9+" : count %>
  </span>
<% else %>
  <span id="notification_badge"></span>
<% end %>
```

**Verification:**
```bash
bin/rails console
# Render partial: ApplicationController.render(partial: "notifications/badge", locals: { count: 5 })
```

---

### Step 5.2: Update Navbar with Notification Dropdown

**Files to modify:**
- `app/views/shared/_navbar.html.erb`

**Implementation details:**

Replace the existing notification button section (around lines 29-34) with:
```erb
<%# Notifications Dropdown %>
<div data-controller="notifications"
     data-notifications-user-id-value="<%= current_user&.id %>"
     class="relative">
  <button type="button"
          data-action="click->notifications#toggle"
          class="relative text-slate-400 hover:text-slate-600 p-2 rounded-lg hover:bg-slate-100">
    <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
    </svg>
    <%= render "notifications/badge", count: current_user&.notifications&.unread&.count || 0 %>
  </button>

  <%# Dropdown Panel %>
  <div data-notifications-target="dropdown"
       class="hidden absolute right-0 mt-2 w-96 bg-white dark:bg-slate-800
              rounded-lg shadow-lg border border-slate-200 dark:border-slate-700 z-50">

    <%# Header %>
    <div class="p-3 border-b border-slate-200 dark:border-slate-700 flex justify-between items-center">
      <span class="font-semibold text-slate-900 dark:text-slate-100">Notifications</span>
      <button data-action="click->notifications#markAllRead"
              class="text-sm text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300">
        Mark all read
      </button>
    </div>

    <%# List %>
    <div id="notifications_list" class="max-h-96 overflow-y-auto">
      <% if current_user %>
        <%= turbo_stream_from "notifications_user_#{current_user.id}" %>
        <%= render "notifications/list", notifications: current_user.notifications.for_dropdown %>
      <% end %>
    </div>

    <%# Footer %>
    <div class="p-3 border-t border-slate-200 dark:border-slate-700 text-center">
      <%= link_to "View all notifications", notifications_path,
          class: "text-sm text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300" %>
    </div>
  </div>
</div>
```

**Verification:**
- Start development server with `bin/dev`
- Check that the bell icon appears in navbar
- Click the bell icon to verify dropdown appears

---

## Phase 6: Stimulus Controllers

### Step 6.1: Create Notifications Controller

**Files to create:**
- `app/javascript/controllers/notifications_controller.js`

**Implementation details:**

`app/javascript/controllers/notifications_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown"]
  static values = { userId: Number }

  connect() {
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
    document.addEventListener("click", this.boundCloseOnClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.classList.toggle("hidden")
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  markAllRead(event) {
    event.preventDefault()
    event.stopPropagation()

    fetch("/notifications/mark_all_read", {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
  }
}
```

**Verification:**
```bash
bin/rails stimulus:manifest:update
# Manual: Test dropdown toggle and mark all read functionality
```

---

### Step 6.2: Create Notification Item Controller

**Files to create:**
- `app/javascript/controllers/notification_item_controller.js`

**Implementation details:**

`app/javascript/controllers/notification_item_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details"]
  static values = { id: Number, expanded: Boolean, read: Boolean }

  toggle(event) {
    // Don't toggle if clicking on a link
    if (event.target.tagName === "A") return

    this.expandedValue = !this.expandedValue
    this.detailsTarget.classList.toggle("hidden", !this.expandedValue)

    if (this.expandedValue && !this.readValue) {
      this.markAsRead()
    }
  }

  markAsRead() {
    fetch(`/notifications/${this.idValue}/mark_read`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    }).then(() => {
      this.readValue = true
    })
  }
}
```

**Verification:**
```bash
bin/rails stimulus:manifest:update
# Manual: Click notification item to expand and verify it marks as read
```

---

### Step 6.3: Register Controllers in index.js

**Files to modify:**
- `app/javascript/controllers/index.js`

**Implementation details:**

Add to `app/javascript/controllers/index.js`:
```javascript
import NotificationsController from "./notifications_controller"
application.register("notifications", NotificationsController)

import NotificationItemController from "./notification_item_controller"
application.register("notification-item", NotificationItemController)
```

**Verification:**
```bash
bin/rails stimulus:manifest:update
# Check no errors in browser console
```

---

## Phase 7: Notification Partials

### Step 7.1: Create Status Icon Partials

**Files to create:**
- `app/views/notifications/icons/_clock.html.erb`
- `app/views/notifications/icons/_spinner.html.erb`
- `app/views/notifications/icons/_check_circle.html.erb`
- `app/views/notifications/icons/_x_circle.html.erb`

**Implementation details:**

`_clock.html.erb`:
```erb
<svg class="<%= local_assigns[:class] || 'w-5 h-5' %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
</svg>
```

`_spinner.html.erb`:
```erb
<svg class="<%= local_assigns[:class] || 'w-5 h-5' %>" fill="none" viewBox="0 0 24 24">
  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
</svg>
```

`_check_circle.html.erb`:
```erb
<svg class="<%= local_assigns[:class] || 'w-5 h-5' %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
</svg>
```

`_x_circle.html.erb`:
```erb
<svg class="<%= local_assigns[:class] || 'w-5 h-5' %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
</svg>
```

**Verification:**
```bash
# Verify files exist and render correctly
bin/rails console
# ApplicationController.render(partial: "notifications/icons/check_circle", locals: { class: "w-6 h-6" })
```

---

### Step 7.2: Create Notification Item Partial

**Files to create:**
- `app/views/notifications/_notification.html.erb`

**Implementation details:**

`app/views/notifications/_notification.html.erb`:
```erb
<%= tag.div id: dom_id(notification),
            class: "notification-item p-3 border-b border-slate-100 dark:border-slate-700
                    hover:bg-slate-50 dark:hover:bg-slate-700/50 cursor-pointer
                    #{notification.read? ? 'opacity-60' : ''}",
            data: {
              controller: "notification-item",
              notification_item_id_value: notification.id,
              notification_item_expanded_value: false,
              notification_item_read_value: notification.read?
            } do %>

  <div data-action="click->notification-item#toggle" class="flex items-start gap-3">
    <%# Status icon %>
    <div class="mt-0.5 flex-shrink-0">
      <% case notification.status %>
      <% when "pending" %>
        <%= render "notifications/icons/clock", class: "w-5 h-5 text-slate-400" %>
      <% when "running" %>
        <%= render "notifications/icons/spinner", class: "w-5 h-5 text-teal-500 animate-spin" %>
      <% when "completed" %>
        <%= render "notifications/icons/check_circle", class: "w-5 h-5 text-emerald-500" %>
      <% when "failed" %>
        <%= render "notifications/icons/x_circle", class: "w-5 h-5 text-red-500" %>
      <% end %>
    </div>

    <%# Content %>
    <div class="flex-1 min-w-0">
      <div class="flex items-center justify-between gap-2">
        <p class="text-sm font-medium text-slate-900 dark:text-slate-100 truncate">
          <%= notification.title %>
        </p>
        <% unless notification.read? %>
          <span class="w-2 h-2 bg-teal-500 rounded-full flex-shrink-0"></span>
        <% end %>
      </div>
      <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
        <%= time_ago_in_words(notification.created_at) %> ago
      </p>

      <%# Progress bar (when running) %>
      <% if notification.running? && notification.progress_percent %>
        <div class="mt-2 h-1.5 bg-slate-200 dark:bg-slate-600 rounded-full overflow-hidden">
          <div class="h-full bg-teal-500 transition-all duration-300"
               style="width: <%= notification.progress_percent %>%"></div>
        </div>
        <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
          <%= notification.progress_percent %>% complete
        </p>
      <% end %>
    </div>
  </div>

  <%# Expanded details (hidden by default) %>
  <div data-notification-item-target="details" class="hidden mt-3 pl-8">
    <% if notification.message.present? %>
      <p class="text-sm text-slate-600 dark:text-slate-300 mb-2"><%= notification.message %></p>
    <% end %>

    <% if notification.resource.present? %>
      <%= link_to polymorphic_path(notification.resource),
          class: "text-sm text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300" do %>
        View <%= notification.resource_type.underscore.humanize.downcase %> &rarr;
      <% end %>
    <% end %>
  </div>
<% end %>
```

**Verification:**
```bash
bin/rails console
# Create test notification and render:
# n = Notification.create!(user: User.first, notification_type: "agent_install", title: "Test", status: "running")
# ApplicationController.render(partial: "notifications/notification", locals: { notification: n })
```

---

### Step 7.3: Create List Partial

**Files to create:**
- `app/views/notifications/_list.html.erb`

**Implementation details:**

`app/views/notifications/_list.html.erb`:
```erb
<div id="notifications_list">
  <% if notifications.any? %>
    <%= render notifications %>
  <% else %>
    <div class="p-6 text-center text-slate-500 dark:text-slate-400">
      <svg class="mx-auto h-8 w-8 text-slate-400 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
      </svg>
      <p class="text-sm">No notifications</p>
    </div>
  <% end %>
</div>
```

**Verification:**
```bash
bin/rails console
# ApplicationController.render(partial: "notifications/list", locals: { notifications: User.first.notifications.for_dropdown })
```

---

## Phase 8: Dedicated Page

### Step 8.1: Create Notifications Index View

**Files to create:**
- `app/views/notifications/index.html.erb`

**Implementation details:**

`app/views/notifications/index.html.erb`:
```erb
<div class="container mx-auto px-4 py-6">
  <%# Header %>
  <div class="flex items-center justify-between mb-6">
    <div>
      <h1 class="text-2xl font-bold text-slate-900 dark:text-slate-100">Notifications</h1>
      <p class="text-sm text-slate-500 dark:text-slate-400 mt-1">
        <%= @unread_count %> unread notification<%= @unread_count == 1 ? "" : "s" %>
      </p>
    </div>
    <div class="flex gap-2">
      <%= button_to "Mark all read", mark_all_read_notifications_path,
          method: :post,
          class: "px-3 py-2 text-sm font-medium text-teal-600 hover:text-teal-700
                  bg-teal-50 hover:bg-teal-100 rounded-lg transition-colors
                  dark:text-teal-400 dark:bg-teal-900/30 dark:hover:bg-teal-900/50" %>
      <%= button_to "Archive read", archive_read_notifications_path,
          method: :post,
          class: "px-3 py-2 text-sm font-medium text-slate-600 hover:text-slate-700
                  bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors
                  dark:text-slate-400 dark:bg-slate-700 dark:hover:bg-slate-600" %>
    </div>
  </div>

  <%# Filters %>
  <div class="bg-white dark:bg-slate-800 rounded-lg shadow-sm border border-slate-200 dark:border-slate-700 p-4 mb-6">
    <%= form_with url: notifications_path, method: :get, data: { turbo_frame: "_top" }, class: "flex flex-wrap gap-4" do |f| %>
      <div class="flex-1 min-w-[150px]">
        <%= f.label :status, "Status", class: "block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1" %>
        <%= f.select :status,
            options_for_select([["All Statuses", ""], ["Pending", "pending"], ["Running", "running"], ["Completed", "completed"], ["Failed", "failed"]], params[:status]),
            {},
            class: "w-full rounded-lg border-slate-300 dark:border-slate-600 dark:bg-slate-700 text-sm" %>
      </div>
      <div class="flex-1 min-w-[150px]">
        <%= f.label :type, "Type", class: "block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1" %>
        <%= f.select :type,
            options_for_select([["All Types", ""], ["Agent Install", "agent_install"], ["Agent Update", "agent_update"], ["Benchmark", "benchmark"], ["Inventory", "inventory_collect"], ["Product Sync", "product_sync"]], params[:type]),
            {},
            class: "w-full rounded-lg border-slate-300 dark:border-slate-600 dark:bg-slate-700 text-sm" %>
      </div>
      <div class="flex items-end gap-2">
        <label class="flex items-center gap-2 text-sm text-slate-600 dark:text-slate-400">
          <%= f.check_box :show_archived, { checked: params[:show_archived] == "true" }, "true", "false" %>
          Show archived
        </label>
      </div>
      <div class="flex items-end">
        <%= f.submit "Filter", class: "px-4 py-2 bg-teal-600 hover:bg-teal-700 text-white text-sm font-medium rounded-lg transition-colors cursor-pointer" %>
      </div>
    <% end %>
  </div>

  <%# Notification List %>
  <div class="bg-white dark:bg-slate-800 rounded-lg shadow-sm border border-slate-200 dark:border-slate-700 divide-y divide-slate-200 dark:divide-slate-700">
    <% if @notifications.any? %>
      <% @notifications.each do |notification| %>
        <%= render "notifications/notification_row", notification: notification %>
      <% end %>
    <% else %>
      <div class="p-12 text-center">
        <svg class="mx-auto h-12 w-12 text-slate-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
        </svg>
        <h3 class="text-lg font-medium text-slate-900 dark:text-slate-100 mb-1">No notifications found</h3>
        <p class="text-sm text-slate-500 dark:text-slate-400">
          <% if params[:status].present? || params[:type].present? %>
            Try adjusting your filters
          <% else %>
            You're all caught up!
          <% end %>
        </p>
      </div>
    <% end %>
  </div>

  <%# Pagination %>
  <% if @notifications.respond_to?(:total_pages) && @notifications.total_pages > 1 %>
    <div class="mt-6 flex justify-center">
      <%= paginate @notifications %>
    </div>
  <% end %>
</div>
```

**Verification:**
- Visit `/notifications` in browser
- Test filters and pagination

---

### Step 8.2: Create Notification Row Partial for Index Page

**Files to create:**
- `app/views/notifications/_notification_row.html.erb`

**Implementation details:**

`app/views/notifications/_notification_row.html.erb`:
```erb
<div id="<%= dom_id(notification) %>"
     class="p-4 hover:bg-slate-50 dark:hover:bg-slate-700/50 transition-colors
            <%= notification.read? ? 'opacity-70' : '' %>
            <%= notification.archived? ? 'bg-slate-50 dark:bg-slate-800/50' : '' %>">
  <div class="flex items-start gap-4">
    <%# Status icon %>
    <div class="flex-shrink-0 mt-1">
      <% case notification.status %>
      <% when "pending" %>
        <%= render "notifications/icons/clock", class: "w-6 h-6 text-slate-400" %>
      <% when "running" %>
        <%= render "notifications/icons/spinner", class: "w-6 h-6 text-teal-500 animate-spin" %>
      <% when "completed" %>
        <%= render "notifications/icons/check_circle", class: "w-6 h-6 text-emerald-500" %>
      <% when "failed" %>
        <%= render "notifications/icons/x_circle", class: "w-6 h-6 text-red-500" %>
      <% end %>
    </div>

    <%# Content %>
    <div class="flex-1 min-w-0">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h3 class="text-sm font-medium text-slate-900 dark:text-slate-100">
            <%= notification.title %>
            <% unless notification.read? %>
              <span class="inline-block w-2 h-2 bg-teal-500 rounded-full ml-1"></span>
            <% end %>
          </h3>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
            <span class="capitalize"><%= notification.notification_type.humanize %></span>
            &middot;
            <%= notification.created_at.strftime("%b %d, %Y at %l:%M %p") %>
            <% if notification.completed_at %>
              &middot;
              Duration: <%= distance_of_time_in_words(notification.started_at || notification.created_at, notification.completed_at) %>
            <% end %>
          </p>
        </div>
        <div class="flex-shrink-0">
          <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium
                       <%= case notification.status
                           when 'pending' then 'bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300'
                           when 'running' then 'bg-teal-100 text-teal-700 dark:bg-teal-900/30 dark:text-teal-300'
                           when 'completed' then 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300'
                           when 'failed' then 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300'
                           end %>">
            <%= notification.status.capitalize %>
          </span>
        </div>
      </div>

      <%# Progress bar %>
      <% if notification.running? && notification.progress_percent %>
        <div class="mt-3">
          <div class="flex justify-between text-xs text-slate-500 dark:text-slate-400 mb-1">
            <span><%= notification.message || "Processing..." %></span>
            <span><%= notification.progress_percent %>%</span>
          </div>
          <div class="h-2 bg-slate-200 dark:bg-slate-600 rounded-full overflow-hidden">
            <div class="h-full bg-teal-500 transition-all duration-300"
                 style="width: <%= notification.progress_percent %>%"></div>
          </div>
        </div>
      <% end %>

      <%# Message %>
      <% if notification.message.present? && !notification.running? %>
        <p class="mt-2 text-sm text-slate-600 dark:text-slate-300">
          <%= notification.message %>
        </p>
      <% end %>

      <%# Actions %>
      <div class="mt-3 flex items-center gap-4">
        <% if notification.resource.present? %>
          <%= link_to polymorphic_path(notification.resource),
              class: "text-sm text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300" do %>
            View <%= notification.resource_type.underscore.humanize.downcase %> &rarr;
          <% end %>
        <% end %>

        <% unless notification.read? %>
          <%= button_to "Mark as read", mark_read_notification_path(notification),
              method: :post,
              class: "text-sm text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200" %>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

**Verification:**
- Visit `/notifications` and verify row layout
- Check that status badges and progress bars display correctly

---

## Phase 9: Job Integration

### Step 9.1: Integrate with Agent::InstallJob

**Files to modify:**
- `app/jobs/agent/install_job.rb`

**Implementation details:**

Modify `perform` method to add notification tracking:
```ruby
def perform(node:, target_host:, arch:, bastion_host: nil, bastion_user:, credentials_cache_key:, server_url:, api_key_id: nil, user_id: nil)
  Rails.logger.debug "[Agent::InstallJob] Starting install for #{target_host} (arch: #{arch})"
  local_binary_path = nil
  notification = nil

  # Create notification if user_id provided
  if user_id.present?
    user = User.find_by(id: user_id)
    if user
      notification = NotificationService.create(
        user: user,
        type: "agent_install",
        title: "Installing agent on #{target_host}",
        resource: node,
        metadata: { arch: arch }
      )
      NotificationService.start(notification)
    end
  end

  # ... existing implementation ...

  # On success (before final broadcast_status):
  NotificationService.complete(notification, success: true,
    message: "Agent installed successfully") if notification

rescue Agent::Errors::LifecycleError => e
  # ... existing error handling ...
  NotificationService.complete(notification, success: false,
    message: "Installation failed: #{e.message}") if notification

rescue => e
  # ... existing error handling ...
  NotificationService.complete(notification, success: false,
    message: "Installation failed: #{e.message}") if notification
end
```

**Important:** Also update the job caller to pass `user_id:` parameter.

**Verification:**
```bash
bin/rspec spec/jobs/agent/install_job_spec.rb
# Manual: Trigger agent install and verify notification appears
```

---

### Step 9.2: Integrate with Agent::UpdateJob

**Files to modify:**
- `app/jobs/agent/update_job.rb`

**Implementation details:**

Similar pattern to InstallJob - wrap the job with notification lifecycle.

**Verification:**
```bash
bin/rspec spec/jobs/agent/update_job_spec.rb
```

---

### Step 9.3: Integrate with Agent::UninstallJob

**Files to modify:**
- `app/jobs/agent/uninstall_job.rb`

**Implementation details:**

Similar pattern - create notification for "agent_uninstall" type.

**Verification:**
```bash
bin/rspec spec/jobs/agent/uninstall_job_spec.rb
```

---

### Step 9.4: Integrate with InventoryCollectJob

**Files to modify:**
- `app/jobs/inventory_collect_job.rb`

**Implementation details:**

Add notification for "inventory_collect" type:
```ruby
def perform(target_node_id, gateway_node_id: nil, user_id: nil, **options)
  target_node = Node.find(target_node_id)
  notification = nil

  if user_id.present?
    user = User.find_by(id: user_id)
    if user
      notification = NotificationService.create(
        user: user,
        type: "inventory_collect",
        title: "Collecting inventory from #{target_node.hostname}",
        resource: target_node
      )
      NotificationService.start(notification)
    end
  end

  # ... existing implementation ...

  # In process_collected_data, on success:
  NotificationService.complete(notification, success: true,
    message: "Inventory collected successfully") if notification

  # In handle_collection_error/handle_ssh_error:
  NotificationService.complete(notification, success: false,
    message: error_message) if notification
end
```

**Verification:**
```bash
bin/rspec spec/jobs/inventory_collect_job_spec.rb
```

---

### Step 9.5: Integrate with Benchmark::TriggerJob

**Files to modify:**
- `app/jobs/benchmark/trigger_job.rb`

**Implementation details:**

Add notification for "benchmark" type with progress updates:
```ruby
def perform(node, run, server_url, agent_token, argument_overrides = {}, user_id: nil)
  notification = nil

  if user_id.present?
    user = User.find_by(id: user_id)
    if user
      notification = NotificationService.create(
        user: user,
        type: "benchmark",
        title: "Running #{run.benchmark_recipe.name} on #{node.hostname}",
        resource: run
      )
      NotificationService.start(notification, progress: 10)
    end
  end

  # ... existing implementation ...

  NotificationService.progress(notification, percent: 50, message: "Benchmark submitted") if notification

  # On success:
  NotificationService.complete(notification, success: true,
    message: "Benchmark started successfully") if notification

  # On failure:
  NotificationService.complete(notification, success: false,
    message: result.error) if notification
end
```

**Verification:**
```bash
bin/rspec spec/jobs/benchmark/trigger_job_spec.rb
```

---

### Step 9.6: Integrate with QctSyncJob

**Files to modify:**
- `app/jobs/qct_sync_job.rb`

**Implementation details:**

Add notification for "product_sync" type:
```ruby
def perform(user_id: nil)
  notification = nil

  if user_id.present?
    user = User.find_by(id: user_id)
    if user
      notification = NotificationService.create(
        user: user,
        type: "product_sync",
        title: "Syncing products from QCT web"
      )
      NotificationService.start(notification)
    end
  end

  result = QctScraperService.new.sync_all

  SyncLog.create!(
    source: "qct",
    products_added: result.added_count,
    products_updated: result.updated_count,
    sync_errors: result.errors,
    completed_at: Time.current
  )

  NotificationService.complete(notification, success: true,
    message: "Synced #{result.added_count} new, #{result.updated_count} updated",
    metadata: { added: result.added_count, updated: result.updated_count }) if notification

  Rails.logger.info "[QctSyncJob] Completed: #{result.added_count} added, #{result.updated_count} updated, #{result.errors.size} errors"
rescue => e
  NotificationService.complete(notification, success: false, message: e.message) if notification
  raise
end
```

**Verification:**
```bash
bin/rspec spec/jobs/qct_sync_job_spec.rb
# Manual: Trigger sync from settings page and verify notification
```

---

### Step 9.7: Update Job Callers to Pass user_id

**Files to modify:**
- Controllers that enqueue the jobs (e.g., `nodes/installs_controller.rb`, `nodes_controller.rb`, `settings/server_products_controller.rb`)

**Implementation details:**

Each controller that enqueues a job should pass `user_id: current_user.id`:
```ruby
# Example in nodes/installs_controller.rb
Agent::InstallJob.perform_later(
  node: @node,
  target_host: target_host,
  # ... other params ...
  user_id: current_user.id
)
```

**Verification:**
- Trigger each job type from UI
- Verify notification appears in dropdown

---

## Quality Verification

### Final Verification Checklist

After completing all phases, run these verification steps:

```bash
# 1. Run linter
bin/rubocop -f github

# 2. Run all tests
bin/rspec

# 3. Run security scan
bin/brakeman

# 4. Manual testing checklist:
# - [ ] Bell icon appears in navbar
# - [ ] Clicking bell opens dropdown
# - [ ] Notifications appear in dropdown
# - [ ] Clicking notification expands details
# - [ ] "Mark all read" clears unread count
# - [ ] Badge updates in real-time when job completes
# - [ ] Progress bar animates for running jobs
# - [ ] "View all notifications" links to /notifications
# - [ ] Filters work on /notifications page
# - [ ] Pagination works on /notifications page
# - [ ] ActionCable updates work across browser tabs
```

---

## Files Summary

### New Files to Create:
1. `db/migrate/XXXXXX_create_notifications.rb`
2. `app/models/notification.rb`
3. `spec/models/notification_spec.rb`
4. `spec/factories/notifications.rb`
5. `app/services/notification_service.rb`
6. `spec/services/notification_service_spec.rb`
7. `app/channels/notifications_channel.rb`
8. `spec/channels/notifications_channel_spec.rb`
9. `app/controllers/notifications_controller.rb`
10. `spec/requests/notifications_spec.rb`
11. `app/javascript/controllers/notifications_controller.js`
12. `app/javascript/controllers/notification_item_controller.js`
13. `app/views/notifications/_badge.html.erb`
14. `app/views/notifications/_notification.html.erb`
15. `app/views/notifications/_list.html.erb`
16. `app/views/notifications/_notification_row.html.erb`
17. `app/views/notifications/index.html.erb`
18. `app/views/notifications/icons/_clock.html.erb`
19. `app/views/notifications/icons/_spinner.html.erb`
20. `app/views/notifications/icons/_check_circle.html.erb`
21. `app/views/notifications/icons/_x_circle.html.erb`

### Files to Modify:
1. `app/models/user.rb` - Add has_many :notifications
2. `config/routes.rb` - Add notification routes
3. `app/views/shared/_navbar.html.erb` - Add notification dropdown
4. `app/javascript/controllers/index.js` - Register new controllers
5. `app/jobs/agent/install_job.rb` - Add notification integration
6. `app/jobs/agent/update_job.rb` - Add notification integration
7. `app/jobs/agent/uninstall_job.rb` - Add notification integration
8. `app/jobs/inventory_collect_job.rb` - Add notification integration
9. `app/jobs/benchmark/trigger_job.rb` - Add notification integration
10. `app/jobs/qct_sync_job.rb` - Add notification integration
11. Various controllers that enqueue jobs - Pass user_id

---

## Dependencies

- Kaminari gem (for pagination) - already installed based on typical Rails setup
- ActionCable (built into Rails)
- Turbo Streams (Hotwire - already in use)
- Stimulus (already in use)
