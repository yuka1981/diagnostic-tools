# frozen_string_literal: true

# Active Record Encryption configuration
# These keys are used to encrypt sensitive fields like BMC credentials
# In production, these should be stored in Rails credentials or environment variables

Rails.application.configure do
  config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") {
    Rails.application.credentials.dig(:active_record_encryption, :primary_key) ||
      "dev-primary-key-32-chars-long!!!"
  }

  config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") {
    Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) ||
      "dev-deterministic-key-32-chars!!"
  }

  config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") {
    Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) ||
      "dev-key-derivation-salt-32-char!"
  }
end
