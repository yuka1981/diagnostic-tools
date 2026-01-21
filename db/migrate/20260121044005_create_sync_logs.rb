class CreateSyncLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :sync_logs do |t|
      t.string :source, null: false, limit: 50
      t.integer :products_added, default: 0
      t.integer :products_updated, default: 0
      t.jsonb :sync_errors, default: []
      t.datetime :completed_at

      t.timestamps
    end

    add_index :sync_logs, :source
    add_index :sync_logs, :completed_at
  end
end
