# frozen_string_literal: true

class SaltSetting < ApplicationRecord
  validate :base_url_must_be_valid

  def self.current
    first_or_create!
  end

  def configured?
    base_url.present? && username.present? && password.present?
  end

  private

  def base_url_must_be_valid
    return if base_url.blank?

    begin
      uri = URI.parse(base_url)

      unless uri.scheme.in?(%w[http https])
        errors.add(:base_url, "must use http or https scheme")
        return
      end

      if uri.path.present? && uri.path != "/"
        errors.add(:base_url, "must be a base URL without path (e.g., https://salt-master:8000)")
      end

      if uri.query.present?
        errors.add(:base_url, "must not contain query parameters")
      end

      if uri.fragment.present?
        errors.add(:base_url, "must not contain URL fragments")
      end
    rescue URI::InvalidURIError
      errors.add(:base_url, "is not a valid URL")
    end
  end
end
