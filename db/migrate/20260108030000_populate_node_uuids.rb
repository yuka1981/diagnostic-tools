class PopulateNodeUuids < ActiveRecord::Migration[7.2]
  def up
    Node.where(uuid: nil).find_each do |node|
      node.update_column(:uuid, SecureRandom.uuid)
    end
  end

  def down
    # No-op, we don't want to remove uuids once assigned
  end
end
