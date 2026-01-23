# frozen_string_literal: true

class SshSetting < ApplicationRecord
  DEFAULT_AGENT_PATH = "/usr/local/bin/hpc-agent"

  validates :bastion_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true
  validate :server_url_must_be_base_url

  def self.current
    first_or_create!(bastion_port: 22, default_agent_path: DEFAULT_AGENT_PATH)
  end

  private

  def server_url_must_be_base_url
    return if server_url.blank?

    begin
      uri = URI.parse(server_url)

      unless uri.scheme.in?(%w[http https])
        errors.add(:server_url, "must use http or https scheme")
        return
      end

      if uri.path.present? && uri.path != "/"
        errors.add(:server_url, "must be a base URL without path (e.g., https://example.com, not https://example.com/nodes)")
      end
    rescue URI::InvalidURIError
      errors.add(:server_url, "is not a valid URL")
    end
  end
end
