class MigrateExistingSshOverrideFlags < ActiveRecord::Migration[7.2]
  def up
    # Enable override flags for nodes that have custom SSH settings.
    # This preserves their existing behavior after the SSH consolidation,
    # where nodes without overrides will use global defaults.
    SshOverrideMigrationService.migrate_existing_nodes
  end

  def down
    # Data migration - cannot be automatically reversed.
    # Override flags can be manually adjusted if needed.
  end
end
