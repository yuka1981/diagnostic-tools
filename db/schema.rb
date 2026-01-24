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

ActiveRecord::Schema[7.2].define(version: 2026_01_23_151557) do
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

  create_table "agent_binaries", force: :cascade do |t|
    t.bigint "agent_release_id", null: false
    t.string "arch", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_release_id", "arch"], name: "index_agent_binaries_on_agent_release_id_and_arch", unique: true
    t.index ["agent_release_id"], name: "index_agent_binaries_on_agent_release_id"
  end

  create_table "agent_events", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.bigint "user_id"
    t.bigint "agent_release_id"
    t.string "operation", null: false
    t.string "status", default: "pending", null: false
    t.string "from_version"
    t.string "to_version"
    t.text "error_message"
    t.jsonb "error_details", default: {}
    t.boolean "forced", default: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_release_id"], name: "index_agent_events_on_agent_release_id"
    t.index ["created_at"], name: "index_agent_events_on_created_at"
    t.index ["node_id"], name: "index_agent_events_on_node_id"
    t.index ["operation"], name: "index_agent_events_on_operation"
    t.index ["status"], name: "index_agent_events_on_status"
    t.index ["user_id"], name: "index_agent_events_on_user_id"
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
    t.string "agent_version"
    t.string "ssh_password"
    t.datetime "last_heartbeat_at"
    t.string "agent_status", default: "idle"
    t.bigint "rack_id"
    t.integer "rack_position"
    t.integer "rack_height", default: 1
    t.integer "rack_face", default: 0
    t.bigint "server_product_id"
    t.bigint "ssh_profile_id"
    t.boolean "ssh_profile_override", default: false, null: false
    t.boolean "ssh_user_override", default: false
    t.boolean "ssh_port_override", default: false
    t.boolean "ssh_key_override", default: false
    t.boolean "ssh_password_override", default: false
    t.boolean "sudo_credential_override", default: false
    t.boolean "ssh_connect_method_override", default: false
    t.index ["api_key_id"], name: "index_nodes_on_api_key_id"
    t.index ["hostname"], name: "index_nodes_on_hostname", unique: true
    t.index ["rack_id", "rack_face", "rack_position"], name: "index_nodes_on_rack_id_and_rack_face_and_rack_position"
    t.index ["rack_id"], name: "index_nodes_on_rack_id"
    t.index ["role"], name: "index_nodes_on_role"
    t.index ["server_product_id"], name: "index_nodes_on_server_product_id"
    t.index ["source"], name: "index_nodes_on_source"
    t.index ["ssh_profile_id"], name: "index_nodes_on_ssh_profile_id"
    t.index ["uuid"], name: "index_nodes_on_uuid"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "notification_type", null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.string "message"
    t.string "resource_type"
    t.bigint "resource_id"
    t.jsonb "metadata", default: {}
    t.boolean "read", default: false
    t.boolean "archived", default: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_type", "resource_id"], name: "index_notifications_on_resource_type_and_resource_id"
    t.index ["user_id", "archived", "read"], name: "index_notifications_on_user_id_and_archived_and_read"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "profiling_artifacts", force: :cascade do |t|
    t.bigint "profiling_run_id", null: false
    t.string "filename", null: false
    t.string "file_type"
    t.string "file_path"
    t.bigint "file_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "profiling_run_id", "filename" ], name: "index_profiling_artifacts_on_profiling_run_id_and_filename", unique: true
    t.index [ "profiling_run_id" ], name: "index_profiling_artifacts_on_profiling_run_id"
  end

  create_table "profiling_recipes", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "slug", null: false
    t.text "description"
    t.string "tool", default: "perfspect", null: false
    t.string "subcommand", null: false
    t.string "module_name", default: "perfspect/3.13.0", null: false
    t.jsonb "default_options", default: {}
    t.integer "timeout_seconds", default: 300
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "slug" ], name: "index_profiling_recipes_on_slug", unique: true
    t.index [ "status" ], name: "index_profiling_recipes_on_status"
    t.index [ "tool" ], name: "index_profiling_recipes_on_tool"
  end

  create_table "profiling_runs", force: :cascade do |t|
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "node_id", null: false
    t.bigint "profiling_recipe_id"
    t.bigint "user_id"
    t.integer "status", default: 0, null: false
    t.string "subcommand", null: false
    t.jsonb "options", default: {}
    t.jsonb "metrics", default: {}
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "log_content"
    t.text "error_message"
    t.string "artifact_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "node_id", "created_at" ], name: "index_profiling_runs_on_node_id_and_created_at", order: { created_at: :desc }
    t.index [ "node_id" ], name: "index_profiling_runs_on_node_id"
    t.index [ "profiling_recipe_id" ], name: "index_profiling_runs_on_profiling_recipe_id"
    t.index [ "status" ], name: "index_profiling_runs_on_status"
    t.index [ "user_id" ], name: "index_profiling_runs_on_user_id"
    t.index [ "uuid" ], name: "index_profiling_runs_on_uuid", unique: true
  end

  create_table "racks", force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "facility_id", limit: 255
    t.string "asset_tag", limit: 255
    t.integer "u_height", default: 42, null: false
    t.integer "width_mm"
    t.integer "depth_mm"
    t.integer "max_weight_kg"
    t.integer "status", default: 0, null: false
    t.boolean "desc_units", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "room_id", null: false
    t.index ["room_id", "facility_id"], name: "index_racks_on_room_id_and_facility_id", unique: true, where: "(facility_id IS NOT NULL)"
    t.index ["room_id", "name"], name: "index_racks_on_room_id_and_name", unique: true
    t.index ["room_id"], name: "index_racks_on_room_id"
    t.index ["status"], name: "index_racks_on_status"
  end

  create_table "rooms", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.text "description"
    t.decimal "floor_area_sqm", precision: 10, scale: 2
    t.decimal "power_capacity_kw", precision: 10, scale: 2
    t.decimal "cooling_capacity_kw", precision: 10, scale: 2
    t.integer "max_rack_count"
    t.integer "floor_number"
    t.string "building_wing"
    t.string "grid_coordinates"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "name"], name: "index_rooms_on_site_id_and_name", unique: true
    t.index ["site_id"], name: "index_rooms_on_site_id"
  end

  create_table "server_products", force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "product_series", limit: 100
    t.string "form_factor", limit: 20
    t.integer "rack_height", default: 1
    t.string "qct_product_url", limit: 500
    t.string "cpu_generations", default: [], array: true
    t.integer "socket_count"
    t.integer "max_tdp_watts"
    t.integer "max_memory_gb"
    t.integer "dimm_slots"
    t.string "memory_types", default: [], array: true
    t.integer "max_memory_speed_mhz"
    t.jsonb "drive_bays", default: []
    t.jsonb "pcie_slots", default: []
    t.jsonb "power_supply_options", default: []
    t.boolean "gpu_support", default: false
    t.jsonb "network_options", default: []
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_url"
    t.index ["form_factor"], name: "index_server_products_on_form_factor"
    t.index ["name"], name: "index_server_products_on_name", unique: true
    t.index ["product_series"], name: "index_server_products_on_product_series"
  end

  create_table "sites", force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_sites_on_name", unique: true
  end

  create_table "ssh_profiles", force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.integer "ssh_connect_method", default: 0, null: false
    t.integer "ssh_port", default: 22, null: false
    t.string "ssh_user", limit: 255
    t.string "ssh_password"
    t.text "ssh_key"
    t.string "sudo_credential"
    t.string "jump_host", limit: 255
    t.string "jump_user", limit: 255
    t.integer "jump_port"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_ssh_profiles_on_name", unique: true
  end

  create_table "ssh_settings", force: :cascade do |t|
    t.string "bastion_host"
    t.string "bastion_user"
    t.integer "bastion_port", default: 22
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "server_url"
    t.string "benchmark_work_dir"
    t.string "default_agent_path", default: "/usr/local/bin/hpc-agent"
    t.string "ssh_user"
    t.integer "ssh_port", default: 22
    t.text "ssh_key"
    t.string "ssh_password"
    t.string "sudo_credential"
    t.integer "timeout", default: 30
    t.boolean "verify_host_key", default: false
  end

  create_table "sync_logs", force: :cascade do |t|
    t.string "source", limit: 50, null: false
    t.integer "products_added", default: 0
    t.integer "products_updated", default: 0
    t.jsonb "sync_errors", default: []
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_at"], name: "index_sync_logs_on_completed_at"
    t.index ["source"], name: "index_sync_logs_on_source"
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
  add_foreign_key "agent_binaries", "agent_releases"
  add_foreign_key "agent_events", "agent_releases"
  add_foreign_key "agent_events", "nodes"
  add_foreign_key "agent_events", "users"
  add_foreign_key "artifact_indices", "benchmark_runs"
  add_foreign_key "benchmark_runs", "benchmark_recipes"
  add_foreign_key "benchmark_runs", "nodes"
  add_foreign_key "node_states", "nodes"
  add_foreign_key "nodes", "api_keys"
  add_foreign_key "nodes", "racks"
  add_foreign_key "nodes", "server_products"
  add_foreign_key "nodes", "ssh_profiles"
  add_foreign_key "notifications", "users"
  add_foreign_key "profiling_artifacts", "profiling_runs"
  add_foreign_key "profiling_runs", "nodes"
  add_foreign_key "profiling_runs", "profiling_recipes"
  add_foreign_key "profiling_runs", "users"
  add_foreign_key "racks", "rooms"
  add_foreign_key "rooms", "sites"
end
