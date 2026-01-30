class MigrateExistingSshOverrideFlags < ActiveRecord::Migration[7.2]
  def up
    # No-op: SSH override flags and columns are removed in a later migration
    # (RemoveAgentAndSshIntegration). The original SshOverrideMigrationService
    # was deleted as part of the agent removal.
  end

  def down
    # No-op
  end
end
