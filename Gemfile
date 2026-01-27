source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.2.3"
# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
# Pinned to v2.7.x for Tailwind CSS v3 which supports arbitrary values like grid-rows-[0fr]
gem "tailwindcss-rails", "~> 2.7"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# CSV parsing (required from Ruby 3.4.0+) [https://github.com/ruby/csv]
gem "csv"
# Use Redis adapter to run Action Cable in production
gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Authentication [https://github.com/heartcombo/devise]
gem "devise", "~> 4.9"

# SSH client for remote command execution [https://github.com/net-ssh/net-ssh]
gem "net-ssh", "~> 7.2"
gem "net-scp", "~> 4.0"

# Pagination [https://github.com/kaminari/kaminari]
gem "kaminari", "~> 1.2"

# Charts [https://github.com/ankane/chartkick]
gem "chartkick", "~> 5.1"

group :development, :test do
  gem "dotenv-rails"
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # RSpec testing framework [https://rspec.info/]
  gem "rspec-rails", "~> 7.0"

  # FactoryBot for test data generation [https://github.com/thoughtbot/factory_bot_rails]
  gem "factory_bot_rails", "~> 6.4"

  # Faker for generating fake data [https://github.com/faker-ruby/faker]
  gem "faker", "~> 3.4"

  # Shoulda Matchers for common Rails testing patterns [https://github.com/thoughtbot/shoulda-matchers]
  gem "shoulda-matchers", "~> 6.2"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara", "~> 3.40"
  gem "capybara-playwright-driver", "~> 0.5"

  # Database cleaner for test isolation [https://github.com/DatabaseCleaner/database_cleaner]
  gem "database_cleaner-active_record", "~> 2.2"

  # SimpleCov for code coverage [https://github.com/simplecov-ruby/simplecov]
  gem "simplecov", require: false

  # WebMock for stubbing HTTP requests [https://github.com/bblimke/webmock]
  gem "webmock", "~> 3.19"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

gem "view_component", "~> 4.2"

gem "net-ssh-gateway", "~> 2.0"

gem "ed25519", "~> 1.4"
gem "bcrypt_pbkdf", "~> 1.1"
