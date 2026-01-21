# frozen_string_literal: true

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

    add_index :notifications, [ :user_id, :archived, :read ]
    add_index :notifications, [ :user_id, :created_at ]
    add_index :notifications, [ :resource_type, :resource_id ]
  end
end
