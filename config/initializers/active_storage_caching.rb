# frozen_string_literal: true

# Enable HTTP caching for ActiveStorage image variants
# Browsers will cache images locally for 1 year
Rails.application.config.after_initialize do
  ActiveStorage::Representations::ProxyController.class_eval do
    before_action :set_cache_headers

    private

    def set_cache_headers
      expires_in 1.year, public: true
    end
  end
end
