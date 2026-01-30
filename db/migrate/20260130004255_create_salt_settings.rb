class CreateSaltSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :salt_settings do |t|
      t.string :base_url
      t.string :username
      t.string :password
      t.string :ca_cert_path
      t.boolean :verify_ssl, default: true

      t.timestamps
    end
  end
end
