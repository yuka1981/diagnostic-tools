class CreateSshSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :ssh_settings do |t|
      t.string :bastion_host
      t.string :bastion_user
      t.integer :bastion_port, default: 22

      t.timestamps
    end
  end
end
