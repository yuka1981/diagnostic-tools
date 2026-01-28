class CreateMlcInstallations < ActiveRecord::Migration[7.2]
  def change
    create_table :mlc_installations do |t|
      t.string :uuid, null: false, index: { unique: true }
      t.integer :status, null: false, default: 0
      t.integer :source_type, null: false, default: 0
      t.string :source_path
      t.string :binary_path
      t.string :checksum_algorithm
      t.string :checksum_value
      t.boolean :checksum_verified, default: false
      t.string :detected_version
      t.string :install_dir, default: "/opt/qct/utils/qis/software"
      t.string :module_dir, default: "/opt/qct/utils/qis/modulefiles"
      t.integer :failure_mode, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
