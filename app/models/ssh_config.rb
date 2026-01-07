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
end
