# Salt API Settings Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Salt API settings page under Admin so users can configure Salt master connection credentials, test connectivity, view the webhook URL, and see Salt master status — all from the UI.

**Architecture:** New `SaltSetting` singleton model (mirrors `SshSetting` pattern), new `Settings::SaltApiController` with show/update/test_connection actions, new view under `/settings/salt_api`. `SaltApiClient` updated to read from DB first, falling back to Rails credentials then env vars. Supports both HTTP and HTTPS connections with optional SSL verification.

**Tech Stack:** Rails 7.2, Hotwire (Turbo), Tailwind CSS, RSpec, FactoryBot

---

### Task 1: Create SaltSetting Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_salt_settings.rb`

**Step 1: Generate the migration**

Run:
```bash
bin/rails generate migration CreateSaltSettings base_url:string username:string password:string ca_cert_path:string verify_ssl:boolean
```

**Step 2: Edit the migration to set defaults**

The generated migration should look like:

```ruby
class CreateSaltSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :salt_settings do |t|
      t.string :base_url
      t.string :username
      t.string :password
      t.string :ca_cert_path
      t.boolean :verify_ssl, default: true

      t.timestamps
    end
  end
end
```

**Step 3: Run the migration**

Run: `bin/rails db:migrate`

**Step 4: Commit**

```bash
git add db/migrate/*_create_salt_settings.rb db/schema.rb
git commit -m "feat: add salt_settings table for Salt API configuration"
```

---

### Task 2: Create SaltSetting Model

**Files:**
- Create: `app/models/salt_setting.rb`
- Create: `spec/models/salt_setting_spec.rb`

**Step 1: Write the failing tests**

Create `spec/models/salt_setting_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SaltSetting, type: :model do
  describe ".current" do
    it "creates a default record when none exists" do
      expect { SaltSetting.current }.to change(SaltSetting, :count).from(0).to(1)
    end

    it "returns the existing record" do
      existing = SaltSetting.create!(base_url: "http://salt:8000")
      expect(SaltSetting.current).to eq(existing)
    end

    it "defaults verify_ssl to true via database default" do
      setting = SaltSetting.current
      expect(setting.verify_ssl).to be true
    end

    it "does not overwrite existing verify_ssl value" do
      SaltSetting.create!(verify_ssl: false)
      setting = SaltSetting.current
      expect(setting.verify_ssl).to be false
    end
  end

  describe "validations" do
    it "allows http URLs" do
      setting = SaltSetting.new(base_url: "http://salt-master:8000")
      setting.valid?
      expect(setting.errors[:base_url]).to be_empty
    end

    it "allows https URLs" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000")
      setting.valid?
      expect(setting.errors[:base_url]).to be_empty
    end

    it "rejects URLs with paths" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000/api")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must be a base URL without path (e.g., https://salt-master:8000)")
    end

    it "rejects non-http schemes" do
      setting = SaltSetting.new(base_url: "ftp://salt-master:8000")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must use http or https scheme")
    end

    it "rejects URLs with query parameters" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000?foo=bar")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must not contain query parameters")
    end

    it "rejects URLs with fragments" do
      setting = SaltSetting.new(base_url: "https://salt-master:8000#section")
      setting.valid?
      expect(setting.errors[:base_url]).to include("must not contain URL fragments")
    end

    it "allows blank base_url" do
      setting = SaltSetting.new(base_url: "")
      setting.valid?
      expect(setting.errors[:base_url]).to be_empty
    end
  end

  describe "#configured?" do
    it "returns true when base_url, username, and password are present" do
      setting = SaltSetting.new(base_url: "http://salt:8000", username: "admin", password: "secret")
      expect(setting.configured?).to be true
    end

    it "returns false when base_url is blank" do
      setting = SaltSetting.new(username: "admin", password: "secret")
      expect(setting.configured?).to be false
    end

    it "returns false when username is blank" do
      setting = SaltSetting.new(base_url: "http://salt:8000", password: "secret")
      expect(setting.configured?).to be false
    end

    it "returns false when password is blank" do
      setting = SaltSetting.new(base_url: "http://salt:8000", username: "admin")
      expect(setting.configured?).to be false
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/models/salt_setting_spec.rb`
Expected: FAIL (class not defined)

**Step 3: Write the model**

Create `app/models/salt_setting.rb`:

```ruby
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
```

**Step 4: Run tests to verify they pass**

Run: `bin/rspec spec/models/salt_setting_spec.rb`
Expected: All pass

**Step 5: Run rubocop**

Run: `bin/rubocop app/models/salt_setting.rb spec/models/salt_setting_spec.rb`

**Step 6: Commit**

```bash
git add app/models/salt_setting.rb spec/models/salt_setting_spec.rb
git commit -m "feat: add SaltSetting model with validations"
```

---

### Task 3: Update SaltApiClient to Read from SaltSetting

**Files:**
- Modify: `app/services/salt_api_client.rb` (constructor, `salt_config`, `execute_request`, `events`)
- Modify: `spec/services/salt_api_client_spec.rb` (add SaltSetting stub + new test)

**Step 1: Add SaltSetting stub to existing tests**

The modified `salt_config` method will call `SaltSetting.current`, which hits the DB. All existing tests construct `SaltApiClient` with explicit params but `salt_config` is still called internally (for `ca_cert` and `verify_ssl` in `execute_request` and `events`). We must stub `SaltSetting` so existing tests don't break.

Add a `before` block inside the top-level `RSpec.describe SaltApiClient do`, before any nested `describe` blocks:

```ruby
before do
  allow(SaltSetting).to receive(:current).and_return(
    instance_double(SaltSetting,
      base_url: nil, username: nil, password: nil,
      ca_cert_path: nil, verify_ssl: true)
  )
end
```

**Step 2: Write the new configuration precedence test**

Add to `spec/services/salt_api_client_spec.rb`, inside the top-level `describe` block, at the end:

```ruby
describe "configuration precedence" do
  it "reads from SaltSetting when no explicit params given" do
    allow(SaltSetting).to receive(:current).and_return(
      instance_double(SaltSetting,
        base_url: "http://salt-from-db:8000",
        username: "db_user",
        password: "db_pass",
        ca_cert_path: "/etc/ssl/salt-ca.pem",
        verify_ssl: false)
    )

    stub_request(:post, "http://salt-from-db:8000/login")
      .to_return(
        status: 200,
        body: { return: [{ token: "db-token", expire: (Time.current + 12.hours).to_f }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    client = described_class.new
    client.authenticate
    expect(WebMock).to have_requested(:post, "http://salt-from-db:8000/login")
  end
end
```

**Step 3: Run test to verify it fails**

Run: `bin/rspec spec/services/salt_api_client_spec.rb -e "reads from SaltSetting"`
Expected: FAIL (still reading from credentials/env)

**Step 4: Update the constructor to accept verify_ssl and ca_cert**

In `app/services/salt_api_client.rb`, replace the constructor (lines 13-18):

Old:
```ruby
  def initialize(base_url: nil, username: nil, password: nil)
    @base_url = base_url || salt_config[:base_url]
    @username = username || salt_config[:username]
    @password = password || salt_config[:password]
    @token = nil
    @token_expires_at = nil
  end
```

New:
```ruby
  def initialize(base_url: nil, username: nil, password: nil, verify_ssl: nil, ca_cert: nil)
    @base_url = base_url || salt_config[:base_url]
    @username = username || salt_config[:username]
    @password = password || salt_config[:password]
    @verify_ssl = verify_ssl.nil? ? salt_config[:verify_ssl] : verify_ssl
    @ca_cert = ca_cert || salt_config[:ca_cert]
    @token = nil
    @token_expires_at = nil
  end
```

**Step 5: Update the salt_config method**

In `app/services/salt_api_client.rb`, replace the `salt_config` method (lines 197-204):

Old:
```ruby
  def salt_config
    @salt_config ||= {
      base_url: Rails.application.credentials.dig(:salt_api, :base_url) || ENV["SALT_API_URL"],
      username: Rails.application.credentials.dig(:salt_api, :username) || ENV["SALT_API_USERNAME"],
      password: Rails.application.credentials.dig(:salt_api, :password) || ENV["SALT_API_PASSWORD"],
      ca_cert: Rails.application.credentials.dig(:salt_api, :ca_cert) || ENV["SALT_API_CA_CERT"]
    }
  end
```

New:
```ruby
  def salt_config
    @salt_config ||= begin
      db_setting = SaltSetting.current
      {
        base_url: db_setting.base_url.presence ||
                  Rails.application.credentials.dig(:salt_api, :base_url) ||
                  ENV["SALT_API_URL"],
        username: db_setting.username.presence ||
                  Rails.application.credentials.dig(:salt_api, :username) ||
                  ENV["SALT_API_USERNAME"],
        password: db_setting.password.presence ||
                  Rails.application.credentials.dig(:salt_api, :password) ||
                  ENV["SALT_API_PASSWORD"],
        ca_cert: db_setting.ca_cert_path.presence ||
                 Rails.application.credentials.dig(:salt_api, :ca_cert) ||
                 ENV["SALT_API_CA_CERT"],
        verify_ssl: db_setting.verify_ssl
      }
    end
  end
```

**Step 6: Update `execute_request` to use instance variables**

In `app/services/salt_api_client.rb`, update `execute_request` (lines 145-168) to use `@verify_ssl` and `@ca_cert`:

Old (lines 148-152):
```ruby
    http.use_ssl = uri.scheme == "https"
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ca_cert = salt_config[:ca_cert]
      http.ca_file = ca_cert if ca_cert.present?
    end
```

New:
```ruby
    http.use_ssl = uri.scheme == "https"
    if http.use_ssl?
      http.verify_mode = @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.ca_file = @ca_cert if @ca_cert.present?
    end
```

**Step 7: Apply the same change to the `events` method**

Old (lines 95-98):
```ruby
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ca_cert = salt_config[:ca_cert]
      http.ca_file = ca_cert if ca_cert.present?
    end
```

New:
```ruby
    if http.use_ssl?
      http.verify_mode = @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.ca_file = @ca_cert if @ca_cert.present?
    end
```

**Step 8: Run all SaltApiClient tests**

Run: `bin/rspec spec/services/salt_api_client_spec.rb`
Expected: All pass (existing tests use stub, new test verifies DB config)

**Step 9: Run rubocop**

Run: `bin/rubocop app/services/salt_api_client.rb`

**Step 10: Commit**

```bash
git add app/services/salt_api_client.rb spec/services/salt_api_client_spec.rb
git commit -m "feat: SaltApiClient reads config from SaltSetting with fallback"
```

---

### Task 4: Create Settings::SaltApiController

**Files:**
- Create: `app/controllers/settings/salt_api_controller.rb`
- Create: `spec/requests/settings/salt_api_spec.rb`

**Step 1: Write the failing request tests**

Create `spec/requests/settings/salt_api_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::SaltApi", type: :request do
  let(:user) { create(:user, :approver) }

  before do
    sign_in user
  end

  describe "GET /settings/salt_api" do
    it "returns http success" do
      get settings_salt_api_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /settings/salt_api" do
    let(:params) do
      {
        salt_setting: {
          base_url: "http://salt-master:8000",
          username: "saltadmin",
          password: "secret",
          ca_cert_path: "/etc/ssl/salt-ca.pem",
          verify_ssl: false
        }
      }
    end

    it "updates the settings" do
      patch settings_salt_api_path, params: params
      expect(response).to redirect_to(settings_salt_api_path)

      setting = SaltSetting.current
      expect(setting.base_url).to eq("http://salt-master:8000")
      expect(setting.username).to eq("saltadmin")
      expect(setting.verify_ssl).to be false
    end

    it "preserves password when not submitted" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "original")
      patch settings_salt_api_path, params: { salt_setting: { base_url: "http://salt:9000", password: "" } }
      expect(SaltSetting.current.password).to eq("original")
    end

    it "clears password when clear flag is set" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "original")
      patch settings_salt_api_path, params: { salt_setting: { clear_password: "1" } }
      expect(SaltSetting.current.password).to be_nil
    end

    it "renders show with errors for invalid base_url" do
      patch settings_salt_api_path, params: { salt_setting: { base_url: "ftp://invalid" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /settings/salt_api/test_connection" do
    it "returns success when Salt API is reachable" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "secret")

      stub_request(:post, "http://salt:8000/login")
        .to_return(
          status: 200,
          body: { return: [{ token: "t", expire: (Time.current + 1.hour).to_f }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      stub_request(:get, "http://salt:8000/minions")
        .to_return(
          status: 200,
          body: { return: [{ "node-01" => {}, "node-02" => {} }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      post test_connection_settings_salt_api_path, as: :turbo_stream
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Connected")
      expect(response.body).to include("2 minions")
    end

    it "returns failure when Salt API is unreachable" do
      SaltSetting.create!(base_url: "http://salt:8000", username: "admin", password: "bad")

      stub_request(:post, "http://salt:8000/login")
        .to_return(status: 401, body: "Unauthorized")

      post test_connection_settings_salt_api_path, as: :turbo_stream
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Failed")
    end

    it "returns not configured when settings are blank" do
      post test_connection_settings_salt_api_path, as: :turbo_stream
      expect(response).to have_http_status(:success)
      expect(response.body).to include("not configured")
    end
  end

  context "as a viewer" do
    let(:viewer) { create(:user, role: :viewer) }

    before { sign_in viewer }

    it "redirects to root" do
      get settings_salt_api_path
      expect(response).to redirect_to(root_path)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/requests/settings/salt_api_spec.rb`
Expected: FAIL (no route, no controller)

**Step 3: Add the route**

In `config/routes.rb`, inside the `namespace :settings` block (line 48-55), add after the `ssh_defaults` line:

Old:
```ruby
  namespace :settings do
    resource :ssh_defaults, only: [ :show, :update ], controller: :ssh_defaults
    resources :server_products do
```

New:
```ruby
  namespace :settings do
    resource :ssh_defaults, only: [ :show, :update ], controller: :ssh_defaults
    resource :salt_api, only: [ :show, :update ], controller: :salt_api do
      post :test_connection
    end
    resources :server_products do
```

> **Note:** Do NOT use `on: :member` here. Singular `resource` routes have no `:id` segment, so `on: :member` is semantically incorrect. Declaring the action directly in the block generates the correct path `/settings/salt_api/test_connection`.

**Step 4: Create the controller**

Create `app/controllers/settings/salt_api_controller.rb`:

```ruby
# frozen_string_literal: true

module Settings
  class SaltApiController < ApplicationController
    layout "dashboard"
    before_action :authenticate_user!
    before_action :authorize_approver!

    def show
      @salt_setting = SaltSetting.current
      @webhook_url = webhook_url
    end

    def update
      @salt_setting = SaltSetting.current
      update_params = salt_params.to_h

      # Handle password: clear if flag set, otherwise preserve existing when blank
      if update_params.delete(:clear_password) == "1"
        update_params[:password] = nil
      elsif update_params[:password].blank?
        update_params.delete(:password)
      end

      if @salt_setting.update(update_params)
        redirect_to settings_salt_api_path, notice: "Salt API settings updated successfully."
      else
        @webhook_url = webhook_url
        render :show, status: :unprocessable_entity
      end
    end

    def test_connection
      @salt_setting = SaltSetting.current

      unless @salt_setting.configured?
        @test_result = { success: false, message: "Salt API is not configured. Please fill in the connection settings first." }
        render turbo_stream: turbo_stream.replace("test-connection-result", partial: "settings/salt_api/test_result")
        return
      end

      begin
        client = SaltApiClient.new(
          base_url: @salt_setting.base_url,
          username: @salt_setting.username,
          password: @salt_setting.password,
          verify_ssl: @salt_setting.verify_ssl,
          ca_cert: @salt_setting.ca_cert_path
        )
        client.authenticate
        minions = client.get_minions
        minion_count = minions.keys.size
        @test_result = { success: true, message: "Connected successfully. #{minion_count} minions online." }
      rescue SaltApiClient::AuthenticationError => e
        @test_result = { success: false, message: "Authentication failed: #{e.message}" }
      rescue SaltApiClient::TimeoutError => e
        @test_result = { success: false, message: "Connection timed out: #{e.message}" }
      rescue StandardError => e
        @test_result = { success: false, message: "Failed to connect: #{e.message}" }
      end

      render turbo_stream: turbo_stream.replace("test-connection-result", partial: "settings/salt_api/test_result")
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to root_path, alert: "You are not authorized to access this page."
    end

    def webhook_url
      "#{request.base_url}/api/v1/salt/events"
    end

    def salt_params
      params.require(:salt_setting).permit(
        :base_url, :username, :password, :ca_cert_path, :verify_ssl,
        :clear_password
      )
    end
  end
end
```

**Step 5: Run tests to verify they fail on missing views**

Run: `bin/rspec spec/requests/settings/salt_api_spec.rb`
Expected: Likely fails on missing template

**Step 6: Commit controller + route (views in next task)**

```bash
git add app/controllers/settings/salt_api_controller.rb config/routes.rb
git commit -m "feat: add Settings::SaltApiController with test_connection"
```

---

### Task 5: Create Salt API Settings View

**Files:**
- Create: `app/views/settings/salt_api/show.html.erb`
- Create: `app/views/settings/salt_api/_test_result.html.erb`

**Step 1: Create the test result partial**

Create `app/views/settings/salt_api/_test_result.html.erb`:

```erb
<div id="test-connection-result">
  <% if defined?(@test_result) && @test_result %>
    <div class="mt-3 p-3 rounded text-sm <%= @test_result[:success] ? 'bg-emerald-50 border border-emerald-200 text-emerald-800' : 'bg-error-1 border border-error-2 text-error-7' %>">
      <div class="flex items-center gap-2">
        <% if @test_result[:success] %>
          <%= lucide_icon("check-circle", class: "h-4 w-4 text-emerald-600") %>
          <span class="font-bold">Connected</span>
        <% else %>
          <%= lucide_icon("x-circle", class: "h-4 w-4 text-error-6") %>
          <span class="font-bold">Failed</span>
        <% end %>
      </div>
      <p class="mt-1"><%= @test_result[:message] %></p>
    </div>
  <% end %>
</div>
```

**Step 2: Create the main show view**

Create `app/views/settings/salt_api/show.html.erb`:

```erb
<% content_for(:page_title) { "Salt API" } %>

<div class="space-y-6" data-testid="salt-api-settings-container">
  <%# Connection Settings Card %>
  <div class="card-netbox">
    <div class="card-header">
      <h2 class="card-title">Salt API Connection</h2>
    </div>

    <%= form_with(model: @salt_setting, url: settings_salt_api_path, method: :patch, data: { testid: "salt-api-settings-form" }) do |f| %>
      <div class="p-4 space-y-6">
        <%# API Connection Section %>
        <div>
          <h3 class="text-sm font-bold text-neutral-85 border-b border-neutral-8 pb-2 mb-4">API Endpoint</h3>
          <p class="text-[10px] text-neutral-45 italic mb-4">The Salt API (salt-api / CherryPy) endpoint URL. Supports both HTTP and HTTPS.</p>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-6">
            <div class="sm:col-span-6">
              <%= f.label :base_url, "Salt API URL", class: "block text-xs font-bold text-neutral-85 mb-1" %>
              <%= f.text_field :base_url, placeholder: "e.g. https://salt-master:8000 or http://salt-master:8000", data: { testid: "salt-api-input-url" }, class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
              <p class="text-[10px] text-neutral-45 mt-1">Base URL without trailing path. Both http:// and https:// are supported.</p>
            </div>
          </div>
        </div>

        <%# Authentication Section %>
        <div>
          <h3 class="text-sm font-bold text-neutral-85 border-b border-neutral-8 pb-2 mb-4">Authentication</h3>
          <p class="text-[10px] text-neutral-45 italic mb-4">PAM credentials for authenticating with the Salt API.</p>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-6">
            <div class="sm:col-span-3">
              <%= f.label :username, "Username", class: "block text-xs font-bold text-neutral-85 mb-1" %>
              <%= f.text_field :username, placeholder: "e.g. saltadmin", autocomplete: "off", data: { testid: "salt-api-input-username" }, class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
            </div>

            <div class="sm:col-span-3">
              <%= f.label :password, "Password", class: "block text-xs font-bold text-neutral-85 mb-1" %>
              <%= f.password_field :password, placeholder: @salt_setting.password.present? ? "••••••••" : "Enter password", autocomplete: "off", data: { testid: "salt-api-input-password" }, class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
              <p class="text-[10px] text-neutral-45 mt-1">Leave blank to keep current password.</p>
            </div>
          </div>
        </div>

        <%# SSL/TLS Section %>
        <div>
          <h3 class="text-sm font-bold text-neutral-85 border-b border-neutral-8 pb-2 mb-4">SSL / TLS</h3>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-6">
            <div class="sm:col-span-6">
              <%= f.label :ca_cert_path, "CA Certificate Path", class: "block text-xs font-bold text-neutral-85 mb-1" %>
              <%= f.text_field :ca_cert_path, placeholder: "e.g. /etc/ssl/certs/salt-ca.pem", data: { testid: "salt-api-input-ca-cert" }, class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
              <p class="text-[10px] text-neutral-45 mt-1">Path to CA certificate file on the server. Only needed for HTTPS with custom CA.</p>
            </div>

            <div class="sm:col-span-6 flex items-center">
              <div class="flex items-center">
                <%= f.check_box :verify_ssl, { data: { testid: "salt-api-checkbox-verify-ssl" }, class: "h-4 w-4 rounded border-neutral-15 text-primary-6 focus:ring-primary-5" } %>
                <%= f.label :verify_ssl, "Verify SSL Certificate", class: "ml-2 text-sm text-neutral-85" %>
                <span class="ml-2 text-[10px] text-neutral-45">(Disable for self-signed certificates in dev/lab)</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <% if @salt_setting.errors.any? %>
        <div class="px-4 pb-4">
          <div class="bg-error-1 border border-error-2 rounded p-3">
            <h4 class="text-sm font-bold text-error-8">Please correct the following errors:</h4>
            <ul class="mt-2 text-sm text-error-7 list-disc list-inside">
              <% @salt_setting.errors.full_messages.each do |message| %>
                <li><%= message %></li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <div class="flex items-center justify-end gap-3 bg-neutral-2 border-t border-neutral-8 px-4 py-3">
        <%= f.submit "Save Settings", data: { testid: "salt-api-button-submit" }, class: "btn-primary" %>
      </div>
    <% end %>
  </div>

  <%# Test Connection Card %>
  <div class="card-netbox">
    <div class="card-header">
      <h2 class="card-title">Test Connection</h2>
    </div>
    <div class="p-4">
      <p class="text-sm text-neutral-65 mb-4">Verify the Salt API connection using the saved settings above.</p>

      <%= button_to "Test Connection",
          test_connection_settings_salt_api_path,
          method: :post,
          data: { testid: "salt-api-button-test", turbo_stream: true },
          class: "btn-secondary" %>

      <%= render "settings/salt_api/test_result" %>
    </div>
  </div>

  <%# Event Webhook URL Card %>
  <div class="card-netbox">
    <div class="card-header">
      <h2 class="card-title">Event Webhook</h2>
    </div>
    <div class="p-4">
      <p class="text-sm text-neutral-65 mb-4">Configure your Salt master reactor to POST events to this URL for real-time benchmark result processing and presence monitoring.</p>

      <div>
        <label class="block text-xs font-bold text-neutral-85 mb-1">Webhook URL</label>
        <div class="flex items-center gap-2">
          <code class="flex-1 block rounded bg-neutral-4 border border-neutral-8 py-1.5 px-3 text-sm text-neutral-85 font-mono" data-testid="salt-api-webhook-url"><%= @webhook_url %></code>
        </div>
        <p class="text-[10px] text-neutral-45 mt-2">
          Add this to your Salt master reactor configuration:<br>
          <code class="text-[10px] bg-neutral-4 px-1 rounded">reactor: [{salt/job/ret/*: [/srv/reactor/webhook.sls]}]</code>
        </p>
      </div>
    </div>
  </div>

  <%# Salt Master Status Card %>
  <div class="card-netbox">
    <div class="card-header">
      <h2 class="card-title">Salt Master Status</h2>
    </div>
    <div class="p-4">
      <% if @salt_setting.configured? %>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <dt class="text-xs font-bold text-neutral-45">Configuration</dt>
            <dd class="mt-1 text-sm text-emerald-600 font-bold flex items-center gap-1">
              <%= lucide_icon("check-circle", class: "h-4 w-4") %> Configured
            </dd>
          </div>
          <div>
            <dt class="text-xs font-bold text-neutral-45">API Endpoint</dt>
            <dd class="mt-1 text-sm text-neutral-85 font-mono"><%= @salt_setting.base_url %></dd>
          </div>
          <div>
            <dt class="text-xs font-bold text-neutral-45">SSL Verification</dt>
            <dd class="mt-1 text-sm text-neutral-85"><%= @salt_setting.verify_ssl? ? "Enabled" : "Disabled" %></dd>
          </div>
        </div>
        <p class="text-[10px] text-neutral-45 mt-4">Use "Test Connection" above to verify the Salt master is reachable and view minion count.</p>
      <% else %>
        <div class="text-sm text-neutral-45 flex items-center gap-2">
          <%= lucide_icon("alert-circle", class: "h-4 w-4 text-amber-500") %>
          Salt API is not configured. Fill in the connection settings above.
        </div>
      <% end %>
    </div>
  </div>
</div>
```

**Step 3: Run the request tests**

Run: `bin/rspec spec/requests/settings/salt_api_spec.rb`
Expected: All pass

**Step 4: Run rubocop on new files**

Run: `bin/rubocop app/views/settings/salt_api/ app/controllers/settings/salt_api_controller.rb`

**Step 5: Commit**

```bash
git add app/views/settings/salt_api/
git commit -m "feat: add Salt API settings views with test connection and webhook display"
```

---

### Task 6: Add Salt API Link to Sidebar

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb` (lines 132-138, after the SSH Defaults link)

**Step 1: Add the sidebar link**

In `app/views/shared/_sidebar.html.erb`, after the SSH Defaults link block (after line 138 `<% end %>`), add:

```erb
          <%= link_to settings_salt_api_path,
              data: { turbo_prefetch: false },
              class: "flex items-center gap-3 px-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/settings/salt_api') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
            <%= lucide_icon("cloud-cog", class: "h-5 w-5 opacity-75") %>
            Salt API
          <% end %>
```

This inserts between the SSH Defaults and Server Products links in the Admin section.

**Step 2: Run the full test suite to make sure nothing is broken**

Run: `bin/rspec`
Expected: All pass

**Step 3: Run rubocop**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 4: Commit**

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "feat: add Salt API link to admin sidebar"
```

---

### Task 7: Final Verification

**Step 1: Run the full test suite**

Run: `bin/rspec`
Expected: All green

**Step 2: Run rubocop**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 3: Run brakeman security scan**

Run: `bin/brakeman`
Expected: No new warnings (password stored in DB as plain string — same pattern as SshSetting.ssh_password. If a concern, can be addressed as follow-up with encrypted attributes.)

**Step 4: Verify manually (optional)**

Run: `bin/dev`
- Navigate to Admin section in sidebar
- Click "Salt API"
- Fill in URL (http or https), username, password
- Save settings
- Click "Test Connection"
- Verify webhook URL is displayed
