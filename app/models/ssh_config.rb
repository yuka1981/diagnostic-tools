# frozen_string_literal: true

# Simplified SshConfig - all methods delegate directly to SshSetting.current
class SshConfig
  def self.jump_host       = SshSetting.current.bastion_host
  def self.jump_user       = SshSetting.current.bastion_user
  def self.jump_port       = SshSetting.current.bastion_port
  def self.user            = SshSetting.current.ssh_user
  def self.ssh_key         = SshSetting.current.ssh_key
  def self.ssh_password    = SshSetting.current.ssh_password
  def self.sudo_credential = SshSetting.current.sudo_credential
  def self.timeout         = SshSetting.current.timeout
  def self.verify_host_key = SshSetting.current.verify_host_key
  def self.use_jump_host?  = jump_host.present?

  # Legacy method for backwards compatibility - returns empty array
  # SSH keys are now stored as key_data (content) not key_path (file)
  def self.key_path = nil
end
