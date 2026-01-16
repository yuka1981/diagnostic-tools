# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_01_16_024022) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_releases", force: :cascade do |t|
    t.string "version", null: false
    t.string "checksum"
    t.text "release_notes"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_agent_releases_on_status"
    t.index ["version"], name: "index_agent_releases_on_version", unique: true
  end

  create_table "api_keys", force: :cascade do |t|
    t.string "name", null: false
    t.string "token", null: false
    t.integer "status", default: 0, null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_api_keys_on_token", unique: true
  end

  create_table "artifact_indices", force: :cascade do |t|
    t.bigint "benchmark_run_id", null: false
    t.string "path"
    t.string "file_type"
    t.bigint "size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stored_path"
    t.index ["benchmark_run_id"], name: "index_artifact_indices_on_benchmark_run_id"
  end

  create_table "benchmark_recipes", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "version", limit: 50, null: false
    t.jsonb "default_profile", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.string "command"
    t.text "description"
    t.integer "timeout_seconds", default: 3600
    t.integer "status", default: 0, null: false
    t.index ["name", "version"], name: "index_benchmark_recipes_on_name_and_version", unique: true
    t.index ["name"], name: "index_benchmark_recipes_on_name"
    t.index ["slug"], name: "index_benchmark_recipes_on_slug", unique: true
  end

  create_table "benchmark_runs", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.bigint "benchmark_recipe_id", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "status", default: 0, null: false
    t.jsonb "metrics", default: {}
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "log_path"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "last_heartbeat_at"
    t.string "current_phase"
    t.text "log_content"
    t.jsonb "arguments", default: {}
    t.index ["benchmark_recipe_id"], name: "index_benchmark_runs_on_benchmark_recipe_id"
    t.index ["node_id", "started_at"], name: "index_benchmark_runs_on_node_id_and_started_at", order: { started_at: :desc }
    t.index ["node_id"], name: "index_benchmark_runs_on_node_id"
    t.index ["started_at"], name: "index_benchmark_runs_on_started_at"
    t.index ["status"], name: "index_benchmark_runs_on_status"
    t.index ["uuid"], name: "index_benchmark_runs_on_uuid", unique: true
  end

  create_table "node_states", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.jsonb "cpu_info", default: {}
    t.jsonb "mem_info", default: {}
    t.jsonb "disk_info", default: []
    t.jsonb "net_info", default: []
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "host_info", default: {}
    t.jsonb "dmi_info", default: {}
    t.jsonb "network_inventory"
    t.index ["captured_at"], name: "index_node_states_on_captured_at"
    t.index ["node_id", "captured_at"], name: "index_node_states_on_node_id_and_captured_at", order: { captured_at: :desc }
    t.index ["node_id"], name: "index_node_states_on_node_id"
  end

  create_table "nodes", force: :cascade do |t|
    t.string "hostname", limit: 255, null: false
    t.string "ip"
    t.integer "role", default: 0, null: false
    t.string "arch"
    t.integer "source", default: 0, null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ssh_port", default: 22, null: false
    t.string "ssh_user"
    t.string "jump_host"
    t.string "jump_user"
    t.integer "jump_port"
    t.string "agent_path"
    t.string "uuid"
    t.integer "ssh_connect_method"
    t.text "ssh_key"
    t.string "sudo_credential"
    t.string "benchmark_work_dir"
    t.string "api_token"
    t.bigint "api_key_id"
    t.index ["api_key_id"], name: "index_nodes_on_api_key_id"
    t.index ["hostname"], name: "index_nodes_on_hostname", unique: true
    t.index ["role"], name: "index_nodes_on_role"
    t.index ["source"], name: "index_nodes_on_source"
    t.index ["uuid"], name: "index_nodes_on_uuid"
  end

  create_table "ssh_settings", force: :cascade do |t|
    t.string "bastion_host"
    t.string "bastion_user"
    t.integer "bastion_port", default: 22
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "server_url"
    t.string "benchmark_work_dir"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name"
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "artifact_indices", "benchmark_runs"
  add_foreign_key "benchmark_runs", "benchmark_recipes"
  add_foreign_key "benchmark_runs", "nodes"
  add_foreign_key "node_states", "nodes"
  add_foreign_key "nodes", "api_keys"
end
