# frozen_string_literal: true

require "capybara/rspec"

# Register Playwright driver
Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(app,
    browser_type: :chromium,
    headless: true
  )
end

Capybara.configure do |config|
  config.default_max_wait_time = 5
  config.default_normalize_ws = true
end

RSpec.configure do |config|
  config.before(:each, type: :system) do |example|
    if example.metadata[:js]
      driven_by :playwright
    else
      driven_by :rack_test
    end
  end
end
