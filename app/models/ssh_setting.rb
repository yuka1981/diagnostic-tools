# frozen_string_literal: true

class SshSetting < ApplicationRecord
  DEFAULT_AGENT_PATH = "/usr/local/bin/hpc-agent"
  VALID_BMC_POLLING_INTERVALS = [ 1, 3, 5 ].freeze

  validates :bastion_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_blank: true
  validates :timeout, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 300 }, allow_blank: true
  validates :bmc_sensor_polling_interval, inclusion: { in: VALID_BMC_POLLING_INTERVALS }, allow_blank: true
  validate :server_url_must_be_base_url
  validate :prometheus_pushgateway_url_must_be_valid
  validate :prometheus_url_must_be_valid

  def self.current
    first_or_create!(
      bastion_port: 22,
      ssh_port: 22,
      timeout: 30,
      verify_host_key: false,
      default_agent_path: DEFAULT_AGENT_PATH,
      bmc_sensor_polling_interval: 5,
      bmc_collection_enabled: false
    )
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

  def prometheus_pushgateway_url_must_be_valid
    validate_url_format(:prometheus_pushgateway_url)
  end

  def prometheus_url_must_be_valid
    validate_url_format(:prometheus_url)
  end

  def validate_url_format(attribute)
    url = send(attribute)
    return if url.blank?

    begin
      uri = URI.parse(url)

      unless uri.scheme.in?(%w[http https])
        errors.add(attribute, "must use http or https scheme")
      end
    rescue URI::InvalidURIError
      errors.add(attribute, "is not a valid URL")
    end
  end
end
