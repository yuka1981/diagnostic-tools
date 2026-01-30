class PopulateNodeUuids < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE nodes SET uuid = gen_random_uuid()::text WHERE uuid IS NULL
    SQL
  end

  def down
    # No-op, we don't want to remove uuids once assigned
  end
end
