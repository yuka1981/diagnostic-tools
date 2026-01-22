# Notification Center Design

**Date:** 2026-01-21
**Status:** Approved

## Overview

A notification center for tracking long-running background tasks. Users can trace task progress in real-time and see a badge when tasks complete.

## Decisions

| Aspect | Decision |
|--------|----------|
| **Scope** | All task types (agent ops, inventory, benchmarks, product sync) |
| **UI Pattern** | Badge + Dropdown + Dedicated Page |
| **Badge Behavior** | Counts unread completions |
| **Mark as Read** | Click to expand marks as read |
| **Click Action** | Expand inline details + optional navigation link |
| **Persistence** | Archive pattern (read → archived, hidden from dropdown) |
| **Real-time** | Per-user ActionCable channel |
| **Job Integration** | Central NotificationService |
| **Data Storage** | Fixed columns + JSONB metadata |

## Data Model

### `notifications` table

```ruby
create_table :notifications do |t|
  t.references :user, null: false, foreign_key: true
  t.string :notification_type, null: false  # "agent_install", "benchmark", "inventory_collect", "product_sync"
  t.string :status, null: false, default: "pending"  # pending, running, completed, failed
  t.string :title, null: false              # "Installing agent on node-01"
  t.string :message                         # "Completed successfully" or error summary
  t.string :resource_type                   # "Node", "BenchmarkRun", etc.
  t.bigint :resource_id                     # ID for navigation link
  t.jsonb :metadata, default: {}            # progress_percent, error_details, result_summary, etc.
  t.boolean :read, default: false
  t.boolean :archived, default: false
  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps
end

add_index :notifications, [:user_id, :archived, :read]
add_index :notifications, [:user_id, :created_at]
```

### Notification model scopes

- `unread` - `where(read: false, archived: false)`
- `active` - `where(archived: false)` (for dropdown)
- `for_dropdown` - `active.order(created_at: :desc).limit(10)`

### Status transitions

`pending → running → completed/failed`

## NotificationService

Central service for creating and updating notifications.

```ruby
# app/services/notification_service.rb
class NotificationService
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
      broadcast_to_user(notification)
      notification
    end

    # Mark as running with optional progress
    def start(notification, progress: nil)
      notification.update!(status: "running", started_at: Time.current)
      notification.metadata["progress_percent"] = progress if progress
      broadcast_to_user(notification)
    end

    # Update progress during execution
    def progress(notification, percent:, message: nil)
      notification.metadata["progress_percent"] = percent
      notification.message = message if message
      notification.save!
      broadcast_to_user(notification)
    end

    # Mark completed (success or failure)
    def complete(notification, success:, message: nil, metadata: {})
      notification.update!(
        status: success ? "completed" : "failed",
        message: message,
        metadata: notification.metadata.merge(metadata),
        completed_at: Time.current
      )
      broadcast_to_user(notification)
      broadcast_badge_update(notification.user)
    end

    private

    def broadcast_to_user(notification)
      Turbo::StreamsChannel.broadcast_replace_to(
        "notifications_user_#{notification.user_id}",
        target: dom_id(notification),
        partial: "notifications/notification",
        locals: { notification: notification }
      )
    end

    def broadcast_badge_update(user)
      count = user.notifications.unread.count
      Turbo::StreamsChannel.broadcast_replace_to(
        "notifications_user_#{user.id}",
        target: "notification_badge",
        partial: "notifications/badge",
        locals: { count: count }
      )
    end
  end
end
```

## UI Components

### Navbar Badge & Dropdown

```erb
<!-- In app/views/shared/_navbar.html.erb -->
<div data-controller="notifications"
     data-notifications-user-id-value="<%= current_user.id %>">
  <button data-action="click->notifications#toggle" class="relative p-2">
    <svg><!-- bell icon --></svg>
    <%= turbo_frame_tag "notification_badge" do %>
      <%= render "notifications/badge", count: current_user.notifications.unread.count %>
    <% end %>
  </button>

  <!-- Dropdown panel (hidden by default) -->
  <div data-notifications-target="dropdown"
       class="hidden absolute right-0 mt-2 w-96 bg-white dark:bg-slate-800
              rounded-lg shadow-lg border border-slate-200 dark:border-slate-700 z-50">

    <div class="p-3 border-b border-slate-200 flex justify-between items-center">
      <span class="font-semibold">Notifications</span>
      <button data-action="click->notifications#markAllRead"
              class="text-sm text-teal-600 hover:text-teal-700">
        Mark all read
      </button>
    </div>

    <div id="notifications_list" class="max-h-96 overflow-y-auto">
      <%= turbo_stream_from "notifications_user_#{current_user.id}" %>
      <%= render current_user.notifications.for_dropdown %>
    </div>

    <div class="p-3 border-t border-slate-200 text-center">
      <%= link_to "View all notifications", notifications_path,
          class: "text-sm text-teal-600 hover:text-teal-700" %>
    </div>
  </div>
</div>
```

### Badge Partial

```erb
<!-- app/views/notifications/_badge.html.erb -->
<% if count > 0 %>
  <span class="absolute -top-1 -right-1 bg-red-500 text-white text-xs
               rounded-full h-5 w-5 flex items-center justify-center">
    <%= count > 9 ? "9+" : count %>
  </span>
<% end %>
```

### Notification Item Partial

```erb
<!-- app/views/notifications/_notification.html.erb -->
<%= tag.div id: dom_id(notification),
            class: "notification-item p-3 border-b border-slate-100 dark:border-slate-700
                    hover:bg-slate-50 dark:hover:bg-slate-700/50 cursor-pointer
                    #{notification.read? ? 'opacity-60' : ''}",
            data: {
              controller: "notification-item",
              notification_item_id_value: notification.id,
              notification_item_expanded_value: false
            } do %>

  <div data-action="click->notification-item#toggle" class="flex items-start gap-3">
    <!-- Status icon -->
    <div class="mt-1">
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

    <!-- Content -->
    <div class="flex-1 min-w-0">
      <div class="flex items-center justify-between">
        <p class="text-sm font-medium text-slate-900 dark:text-slate-100 truncate">
          <%= notification.title %>
        </p>
        <% unless notification.read? %>
          <span class="w-2 h-2 bg-teal-500 rounded-full"></span>
        <% end %>
      </div>
      <p class="text-xs text-slate-500 mt-0.5"><%= time_ago_in_words(notification.created_at) %> ago</p>

      <!-- Progress bar (when running) -->
      <% if notification.status == "running" && notification.metadata["progress_percent"] %>
        <div class="mt-2 h-1.5 bg-slate-200 rounded-full overflow-hidden">
          <div class="h-full bg-teal-500 transition-all"
               style="width: <%= notification.metadata['progress_percent'] %>%"></div>
        </div>
      <% end %>
    </div>
  </div>

  <!-- Expanded details (hidden by default) -->
  <div data-notification-item-target="details" class="hidden mt-3 pl-8">
    <% if notification.message.present? %>
      <p class="text-sm text-slate-600 dark:text-slate-300 mb-2"><%= notification.message %></p>
    <% end %>

    <% if notification.resource_type.present? %>
      <%= link_to "View #{notification.resource_type.underscore.humanize.downcase} →",
          polymorphic_path(notification.resource),
          class: "text-sm text-teal-600 hover:text-teal-700" %>
    <% end %>
  </div>
<% end %>
```

## Stimulus Controllers

### Notifications Controller

```javascript
// app/javascript/controllers/notifications_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["dropdown"]
  static values = { userId: Number }

  connect() {
    this.subscription = createConsumer().subscriptions.create(
      { channel: "NotificationsChannel" },
      { received: this.handleReceived.bind(this) }
    )

    document.addEventListener("click", this.closeOnClickOutside.bind(this))
  }

  disconnect() {
    this.subscription?.unsubscribe()
    document.removeEventListener("click", this.closeOnClickOutside.bind(this))
  }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.classList.toggle("hidden")
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.classList.add("hidden")
    }
  }

  markAllRead() {
    fetch("/notifications/mark_all_read", {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
  }

  handleReceived(data) {
    // Turbo Streams handle DOM updates automatically
  }
}
```

### Notification Item Controller

```javascript
// app/javascript/controllers/notification_item_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details"]
  static values = { id: Number, expanded: Boolean }

  toggle() {
    this.expandedValue = !this.expandedValue
    this.detailsTarget.classList.toggle("hidden", !this.expandedValue)

    if (this.expandedValue) {
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
    })
  }
}
```

## Rails Controller

```ruby
# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :set_notification, only: [:mark_read]

  def index
    @notifications = current_user.notifications
                                 .order(created_at: :desc)
                                 .page(params[:page])

    @notifications = @notifications.where(archived: false) unless params[:show_archived]
    @notifications = @notifications.where(status: params[:status]) if params[:status].present?
    @notifications = @notifications.where(notification_type: params[:type]) if params[:type].present?
  end

  def mark_read
    @notification.update!(read: true)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@notification),
          turbo_stream.replace("notification_badge",
            partial: "notifications/badge",
            locals: { count: current_user.notifications.unread.count })
        ]
      end
    end
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read: true)

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
    end
  end

  def archive_read
    current_user.notifications.where(read: true).update_all(archived: true)
    redirect_to notifications_path, notice: "Read notifications archived"
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end
end
```

## Routes

```ruby
# config/routes.rb
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

## ActionCable Channel

```ruby
# app/channels/notifications_channel.rb
class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "notifications_user_#{current_user.id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
```

## Job Integration Examples

### Agent Install Job

```ruby
class Agent::InstallJob < ApplicationJob
  def perform(node:, release:, user:)
    notification = NotificationService.create(
      user: user,
      type: "agent_install",
      title: "Installing agent on #{node.hostname}",
      resource: node,
      metadata: { release_version: release.version }
    )

    NotificationService.start(notification)

    # ... existing install logic ...

    NotificationService.complete(notification, success: true,
      message: "Agent #{release.version} installed successfully")
  rescue => e
    NotificationService.complete(notification, success: false,
      message: "Installation failed: #{e.message}",
      metadata: { error_class: e.class.name, backtrace: e.backtrace.first(5) })
    raise
  end
end
```

### Benchmark Job (with progress)

```ruby
class Benchmark::TriggerJob < ApplicationJob
  def perform(benchmark_run:, user:)
    notification = NotificationService.create(
      user: user,
      type: "benchmark",
      title: "Running #{benchmark_run.benchmark_type} on #{benchmark_run.node.hostname}",
      resource: benchmark_run
    )

    NotificationService.start(notification)

    NotificationService.progress(notification, percent: 25, message: "Building benchmark...")
    build_benchmark(benchmark_run)

    NotificationService.progress(notification, percent: 50, message: "Submitting to Slurm...")
    submit_to_slurm(benchmark_run)

    NotificationService.progress(notification, percent: 75, message: "Waiting for results...")
    wait_for_results(benchmark_run)

    NotificationService.complete(notification, success: true,
      message: "Benchmark completed",
      metadata: { gflops: benchmark_run.result_gflops })
  rescue => e
    NotificationService.complete(notification, success: false, message: e.message)
    raise
  end
end
```

### Product Sync Job

```ruby
class ProductSyncJob < ApplicationJob
  def perform(user:)
    notification = NotificationService.create(
      user: user,
      type: "product_sync",
      title: "Syncing products from QCT web"
    )

    NotificationService.start(notification)

    result = QctProductSyncService.call

    NotificationService.complete(notification, success: true,
      message: "Synced #{result.created} new, #{result.updated} updated",
      metadata: { created: result.created, updated: result.updated, skipped: result.skipped })
  rescue => e
    NotificationService.complete(notification, success: false, message: e.message)
    raise
  end
end
```

## Components to Build

1. `notifications` migration and model
2. `NotificationService` service class
3. `NotificationsChannel` ActionCable channel
4. `NotificationsController` with routes
5. Navbar badge + dropdown partials
6. `notifications_controller.js` Stimulus controller
7. `notification_item_controller.js` Stimulus controller
8. Dedicated notifications index page
9. Integration into existing jobs
