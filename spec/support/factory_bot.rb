# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    # Lint factories before running the test suite
    # Disabled by default to speed up tests, enable when needed
    # FactoryBot.lint
  end
end
