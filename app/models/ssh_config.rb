# frozen_string_literal: true

class SshConfig
  def self.jump_host
    SshSetting.current.bastion_host.presence || ENV["JUMP_HOST"]
  end

  def self.jump_user
    SshSetting.current.bastion_user.presence || ENV["JUMP_USER"]
  end

  def self.jump_port
    SshSetting.current.bastion_port || ENV.fetch("JUMP_PORT", 22).to_i
  end

  def self.use_jump_host?
    jump_host.present?
  end

  def self.user
    Rails.application.credentials.dig(:ssh, :user) || ENV.fetch("SSH_USER", nil)
  end

  def self.key_path
    Rails.application.credentials.dig(:ssh, :key_path) || ENV.fetch("SSH_KEY_PATH", nil)
  end
end
