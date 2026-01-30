# frozen_string_literal: true

# Configure Active Record Encryption keys.
# In production, these should be set via Rails credentials or environment variables.
# For development/test, we use static keys defined here.
if Rails.env.development? || Rails.env.test?
  Rails.application.config.active_record.encryption.primary_key = "test-primary-key-that-is-32-bytes"
  Rails.application.config.active_record.encryption.deterministic_key = "test-deterministic-key-32-bytes!"
  Rails.application.config.active_record.encryption.key_derivation_salt = "test-key-derivation-salt-value!!"
end
