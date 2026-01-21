# frozen_string_literal: true

require "webmock/rspec"

# Disable all net connections by default in tests
# Allow localhost connections for system tests with Capybara
WebMock.disable_net_connect!(allow_localhost: true)
