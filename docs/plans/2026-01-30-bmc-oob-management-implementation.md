# BMC Out-of-Band Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate BMC out-of-band hardware monitoring and inventory collection into the QIS diagnostic tools platform using Salt Stack for collection and TimescaleDB for sensor storage.

**Architecture:** Salt runner module on master queries BMCs via Redfish/IPMI. Results flow through Salt events to Rails services. Sensor readings stored in TimescaleDB hypertable. Inventory snapshots in PostgreSQL JSONB. Discrepancy detection compares in-band vs OOB data.

**Tech Stack:** Rails 7.2, TimescaleDB (PostgreSQL extension), Salt runner module (Python), Chartkick (charts), Hotwire/Turbo (UI)

**Design Document:** `docs/plans/2026-01-30-bmc-oob-management-redesign.md`

---

## Prerequisites

- PostgreSQL 16+ with TimescaleDB extension installable
- Salt master with `ipmitool` installed and Python `requests` available
- Rails encryption keys configured (`bin/rails db:encryption:init` if not already done)

---

## Task 1: Add TimescaleDB and Create Sensor Readings Hypertable

**Files:**
- Modify: `Gemfile` (add timescaledb adapter if needed)
- Create: `db/migrate/TIMESTAMP_enable_timescaledb_extension.rb`
- Create: `db/migrate/TIMESTAMP_create_bmc_sensor_readings.rb`
- Create: `app/models/bmc_sensor_reading.rb`
- Create: `spec/models/bmc_sensor_reading_spec.rb`

**Step 1: Write the model test**

```ruby
# spec/models/bmc_sensor_reading_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmcSensorReading, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:sensor_type) }
    it { is_expected.to validate_presence_of(:sensor_name) }
    it { is_expected.to validate_presence_of(:value) }
    it { is_expected.to validate_presence_of(:unit) }
    it { is_expected.to validate_presence_of(:recorded_at) }
    it { is_expected.to validate_inclusion_of(:sensor_type).in_array(%w[temperature fan power health]) }
  end

  describe "scopes" do
    let(:node) { create(:node) }

    before do
      # Create readings at different times
      BmcSensorReading.insert_all([
        { node_id: node.id, sensor_type: "temperature", sensor_name: "cpu1",
          value: 52.0, unit: "celsius", recorded_at: 2.hours.ago },
        { node_id: node.id, sensor_type: "fan", sensor_name: "fan1",
          value: 4200, unit: "rpm", recorded_at: 1.hour.ago },
        { node_id: node.id, sensor_type: "temperature", sensor_name: "cpu1",
          value: 55.0, unit: "celsius", recorded_at: 30.minutes.ago }
      ])
    end

    it "filters by sensor_type" do
      expect(BmcSensorReading.where(sensor_type: "temperature").count).to eq(2)
    end

    it "filters by node" do
      expect(BmcSensorReading.where(node_id: node.id).count).to eq(3)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/bmc_sensor_reading_spec.rb`
Expected: FAIL — `uninitialized constant BmcSensorReading`

**Step 3: Create the TimescaleDB extension migration**

```ruby
# db/migrate/TIMESTAMP_enable_timescaledb_extension.rb
class EnableTimescaledbExtension < ActiveRecord::Migration[7.2]
  def change
    enable_extension "timescaledb" unless extension_enabled?("timescaledb")
  end
end
```

**Step 4: Create the hypertable migration**

```ruby
# db/migrate/TIMESTAMP_create_bmc_sensor_readings.rb
class CreateBmcSensorReadings < ActiveRecord::Migration[7.2]
  def up
    create_table :bmc_sensor_readings, id: false do |t|
      t.bigint :node_id, null: false
      t.string :sensor_type, null: false
      t.string :sensor_name, null: false
      t.float :value, null: false
      t.string :unit, null: false
      t.string :status
      t.timestamptz :recorded_at, null: false
    end

    add_index :bmc_sensor_readings, [:node_id, :recorded_at, :sensor_type],
              name: "idx_sensor_readings_node_time_type"
    add_foreign_key :bmc_sensor_readings, :nodes

    # Convert to TimescaleDB hypertable with 7-day chunks
    execute <<~SQL
      SELECT create_hypertable('bmc_sensor_readings', 'recorded_at',
        chunk_time_interval => INTERVAL '7 days');
    SQL

    # Enable compression on chunks older than 7 days
    execute <<~SQL
      ALTER TABLE bmc_sensor_readings SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'node_id, sensor_type, sensor_name'
      );
    SQL
    execute "SELECT add_compression_policy('bmc_sensor_readings', INTERVAL '7 days');"
  end

  def down
    drop_table :bmc_sensor_readings
  end
end
```

**Step 5: Create the model**

```ruby
# app/models/bmc_sensor_reading.rb
# frozen_string_literal: true

class BmcSensorReading < ApplicationRecord
  belongs_to :node

  validates :sensor_type, presence: true, inclusion: { in: %w[temperature fan power health] }
  validates :sensor_name, presence: true
  validates :value, presence: true
  validates :unit, presence: true
  validates :recorded_at, presence: true

  scope :for_node, ->(node_id) { where(node_id: node_id) }
  scope :of_type, ->(type) { where(sensor_type: type) }
  scope :since, ->(time) { where("recorded_at >= ?", time) }
  scope :latest, -> { order(recorded_at: :desc) }
end
```

**Step 6: Run migration and tests**

Run: `bin/rails db:migrate && bin/rspec spec/models/bmc_sensor_reading_spec.rb`
Expected: PASS (all green). Note: TimescaleDB extension must be available on the development PostgreSQL instance.

**Step 7: Add factory**

```ruby
# Add to spec/factories/bmc_sensor_readings.rb
FactoryBot.define do
  factory :bmc_sensor_reading do
    node
    sensor_type { "temperature" }
    sensor_name { "cpu1" }
    value { 52.0 }
    unit { "celsius" }
    status { "ok" }
    recorded_at { Time.current }
  end
end
```

**Step 8: Commit**

```bash
git add db/migrate/*timescaledb* db/migrate/*bmc_sensor* db/schema.rb \
  app/models/bmc_sensor_reading.rb spec/models/bmc_sensor_reading_spec.rb \
  spec/factories/bmc_sensor_readings.rb
git commit -m "feat(bmc): add TimescaleDB hypertable for sensor readings"
```

---

## Task 2: Add Encryption and Enums to BMC Models

**Files:**
- Modify: `app/models/bmc_credential.rb`
- Modify: `app/models/bmc_inventory.rb`
- Modify: `app/models/inventory_discrepancy.rb`
- Modify: `app/models/node.rb` (add has_many :bmc_sensor_readings)
- Create: `spec/models/bmc_credential_spec.rb`
- Create: `spec/models/bmc_inventory_spec.rb`
- Create: `spec/models/inventory_discrepancy_spec.rb`

**Step 1: Write tests for BmcCredential**

```ruby
# spec/models/bmc_credential_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmcCredential, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:bmc_address) }
    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:password) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:protocol).with_values(auto: 0, redfish: 1, ipmi: 2) }
  end

  describe "encryption" do
    it "encrypts the password attribute" do
      credential = create(:bmc_credential, password: "secret123")
      # Read raw value from DB — should not be plaintext
      raw = BmcCredential.connection.select_value(
        "SELECT password FROM bmc_credentials WHERE id = #{credential.id}"
      )
      expect(raw).not_to eq("secret123")
      # But model attribute returns decrypted value
      expect(credential.reload.password).to eq("secret123")
    end
  end

  describe ".global_default" do
    it "returns the global default credential" do
      global = create(:bmc_credential, :global_default)
      create(:bmc_credential, node: create(:node))
      expect(BmcCredential.global_default).to eq(global)
    end
  end

  describe ".for_node" do
    let(:node) { create(:node) }

    it "returns node-specific credential when present" do
      node_cred = create(:bmc_credential, node: node)
      create(:bmc_credential, :global_default)
      expect(BmcCredential.for_node(node)).to eq(node_cred)
    end

    it "falls back to global default when no node-specific credential" do
      global = create(:bmc_credential, :global_default)
      expect(BmcCredential.for_node(node)).to eq(global)
    end

    it "returns nil when no credential exists" do
      expect(BmcCredential.for_node(node)).to be_nil
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/bmc_credential_spec.rb`
Expected: FAIL

**Step 3: Update BmcCredential model**

```ruby
# app/models/bmc_credential.rb
# frozen_string_literal: true

class BmcCredential < ApplicationRecord
  belongs_to :node, optional: true

  encrypts :password

  enum :protocol, { auto: 0, redfish: 1, ipmi: 2 }

  validates :bmc_address, presence: true
  validates :username, presence: true
  validates :password, presence: true

  scope :global_default, -> { find_by(is_global_default: true) }

  def self.for_node(node)
    find_by(node: node) || global_default
  end
end
```

**Step 4: Update BmcInventory model**

```ruby
# app/models/bmc_inventory.rb
# frozen_string_literal: true

class BmcInventory < ApplicationRecord
  belongs_to :node

  enum :collection_method, { redfish: 0, ipmi: 1 }

  validates :captured_at, presence: true

  scope :latest_for, ->(node_id) { where(node_id: node_id).order(captured_at: :desc).first }
end
```

**Step 5: Update InventoryDiscrepancy model**

```ruby
# app/models/inventory_discrepancy.rb
# frozen_string_literal: true

class InventoryDiscrepancy < ApplicationRecord
  belongs_to :node

  enum :severity, { info: 0, warning: 1, critical: 2 }

  validates :field_path, presence: true

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  def resolved?
    resolved_at.present?
  end

  def resolve!(note: nil)
    update!(resolved_at: Time.current, resolution_note: note)
  end
end
```

**Step 6: Add has_many :bmc_sensor_readings to Node model**

Add `has_many :bmc_sensor_readings, dependent: :delete_all` to the Node model, alongside the existing BMC associations.

**Step 7: Add/update factories**

```ruby
# spec/factories/bmc_credentials.rb
FactoryBot.define do
  factory :bmc_credential do
    bmc_address { "192.168.1.100" }
    username { "admin" }
    password { "password" }
    protocol { :auto }
    verify_ssl { true }
    is_global_default { false }

    trait :global_default do
      node { nil }
      is_global_default { true }
    end

    trait :redfish do
      protocol { :redfish }
      port { 443 }
    end

    trait :ipmi do
      protocol { :ipmi }
      port { 623 }
    end
  end
end
```

```ruby
# spec/factories/bmc_inventories.rb
FactoryBot.define do
  factory :bmc_inventory do
    node
    processors { [] }
    memory { [] }
    storage { [] }
    network { [] }
    infiniband { [] }
    bios { {} }
    bmc_info { {} }
    collection_method { :redfish }
    captured_at { Time.current }
  end
end
```

```ruby
# spec/factories/inventory_discrepancies.rb
FactoryBot.define do
  factory :inventory_discrepancy do
    node
    field_path { "memory.0.serial" }
    inband_value { "ABC123" }
    bmc_value { "XYZ789" }
    severity { :warning }

    trait :resolved do
      resolved_at { Time.current }
      resolution_note { "Verified correct" }
    end

    trait :critical do
      severity { :critical }
    end
  end
end
```

**Step 8: Run all BMC model tests**

Run: `bin/rspec spec/models/bmc_credential_spec.rb spec/models/bmc_inventory_spec.rb spec/models/inventory_discrepancy_spec.rb spec/models/bmc_sensor_reading_spec.rb`
Expected: PASS

**Step 9: Run rubocop**

Run: `bin/rubocop -f github app/models/bmc_credential.rb app/models/bmc_inventory.rb app/models/inventory_discrepancy.rb app/models/bmc_sensor_reading.rb`
Expected: No offenses

**Step 10: Commit**

```bash
git add app/models/bmc_credential.rb app/models/bmc_inventory.rb \
  app/models/inventory_discrepancy.rb app/models/node.rb \
  app/models/bmc_sensor_reading.rb \
  spec/models/bmc_credential_spec.rb spec/factories/bmc_credentials.rb \
  spec/factories/bmc_inventories.rb spec/factories/inventory_discrepancies.rb
git commit -m "feat(bmc): add encryption, enums, validations to BMC models"
```

---

## Task 3: Add Chartkick Dependency

**Files:**
- Modify: `Gemfile`
- Modify: `app/javascript/application.js` (or equivalent JS entrypoint)
- Modify: `package.json` (add chart.js and adapter)

**Step 1: Add chartkick gem**

Add to Gemfile:
```ruby
gem "chartkick"
```

**Step 2: Install JavaScript dependencies**

```bash
bundle install
npm install chartkick chart.js chartjs-adapter-date-fns date-fns
```

**Step 3: Add to JS entrypoint**

Add to `app/javascript/application.js`:
```javascript
import "chartkick/chart.js"
```

**Step 4: Verify it loads**

Run: `bin/dev` and check browser console for errors.
Expected: No chartkick-related errors

**Step 5: Commit**

```bash
git add Gemfile Gemfile.lock package.json package-lock.json \
  app/javascript/application.js
git commit -m "feat(bmc): add chartkick and chart.js for sensor charts"
```

---

## Task 4: BMC Credential Management UI — Settings Page

**Files:**
- Create: `app/controllers/settings/bmc_credentials_controller.rb`
- Create: `app/views/settings/bmc_credentials/show.html.erb`
- Create: `app/views/settings/bmc_credentials/_form.html.erb`
- Modify: `config/routes.rb` (add settings route)
- Modify: `app/views/shared/_sidebar.html.erb` or equivalent (add nav link)
- Create: `spec/requests/settings/bmc_credentials_spec.rb`

**Step 1: Write the request spec**

```ruby
# spec/requests/settings/bmc_credentials_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::BmcCredentials", type: :request do
  let(:user) { create(:user, role: :admin) }

  before { sign_in user }

  describe "GET /settings/bmc_credentials" do
    it "renders the BMC credentials settings page" do
      get settings_bmc_credentials_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /settings/bmc_credentials" do
    context "when no global default exists" do
      it "creates a global default credential" do
        patch settings_bmc_credentials_path, params: {
          bmc_credential: {
            bmc_address: "192.168.1.1",
            username: "admin",
            password: "secret",
            protocol: "auto"
          }
        }
        expect(response).to redirect_to(settings_bmc_credentials_path)
        expect(BmcCredential.global_default).to be_present
      end
    end

    context "when global default exists" do
      let!(:credential) { create(:bmc_credential, :global_default) }

      it "updates the existing credential" do
        patch settings_bmc_credentials_path, params: {
          bmc_credential: { username: "newadmin" }
        }
        expect(credential.reload.username).to eq("newadmin")
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/settings/bmc_credentials_spec.rb`
Expected: FAIL — route not found

**Step 3: Add route**

Add to `config/routes.rb` inside the `namespace :settings` block:
```ruby
resource :bmc_credentials, only: [:show, :update], controller: :bmc_credentials
```

**Step 4: Create controller**

```ruby
# app/controllers/settings/bmc_credentials_controller.rb
# frozen_string_literal: true

module Settings
  class BmcCredentialsController < ApplicationController
    before_action :authenticate_user!

    def show
      @credential = BmcCredential.global_default || BmcCredential.new(is_global_default: true)
    end

    def update
      @credential = BmcCredential.global_default || BmcCredential.new(is_global_default: true)

      if params[:bmc_credential][:password].blank?
        params[:bmc_credential].delete(:password)
      end

      if @credential.update(credential_params)
        redirect_to settings_bmc_credentials_path, notice: "BMC credentials updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def credential_params
      params.require(:bmc_credential).permit(:bmc_address, :username, :password, :protocol, :port, :verify_ssl)
    end
  end
end
```

**Step 5: Create the view**

Create `app/views/settings/bmc_credentials/show.html.erb` with a form for the global default credential. Follow the existing settings page patterns (check `app/views/settings/salt_api/show.html.erb` for reference). Include fields for: bmc_address, username, password, protocol (select: auto/redfish/ipmi), port, verify_ssl checkbox.

**Step 6: Add sidebar link**

Add a "BMC Credentials" link in the settings section of the sidebar navigation, following the existing pattern for "Salt API" link.

**Step 7: Run tests and lint**

Run: `bin/rspec spec/requests/settings/bmc_credentials_spec.rb && bin/rubocop -f github app/controllers/settings/bmc_credentials_controller.rb`
Expected: PASS, no offenses

**Step 8: Commit**

```bash
git add app/controllers/settings/bmc_credentials_controller.rb \
  app/views/settings/bmc_credentials/ config/routes.rb \
  spec/requests/settings/bmc_credentials_spec.rb
git commit -m "feat(bmc): add global BMC credential settings page"
```

---

## Task 5: Per-Node BMC Credential Form

**Files:**
- Modify: `app/views/nodes/_form.html.erb` or node edit view (add BMC credential section)
- Modify: `app/controllers/nodes_controller.rb` (handle nested BMC credential params)
- Modify: `spec/requests/nodes_spec.rb` or equivalent (add BMC credential test cases)

**Step 1: Write the test**

Add test case to existing nodes request spec:

```ruby
describe "PATCH /nodes/:id" do
  context "with BMC credential params" do
    let(:node) { create(:node) }

    it "creates a BMC credential for the node" do
      patch node_path(node), params: {
        node: {
          bmc_credential_attributes: {
            bmc_address: "10.0.0.100",
            username: "admin",
            password: "secret",
            protocol: "ipmi"
          }
        }
      }
      expect(node.reload.bmc_credential).to be_present
      expect(node.bmc_credential.bmc_address).to eq("10.0.0.100")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/nodes_spec.rb` (or relevant spec file)
Expected: FAIL

**Step 3: Add accepts_nested_attributes_for to Node model**

Add to `app/models/node.rb`:
```ruby
accepts_nested_attributes_for :bmc_credential, update_only: true, reject_if: :all_blank
```

**Step 4: Permit nested params in NodesController**

Add `bmc_credential_attributes: [:bmc_address, :username, :password, :protocol, :port, :verify_ssl]` to the permitted params in the nodes controller.

**Step 5: Add BMC section to node form**

Add a collapsible "BMC Configuration" section to the node edit form with fields for bmc_address, username, password, protocol, port. Use `fields_for :bmc_credential` for nested attributes. Follow existing form patterns in the codebase.

**Step 6: Run tests and lint**

Run: `bin/rspec spec/requests/nodes_spec.rb && bin/rubocop -f github`
Expected: PASS, no offenses

**Step 7: Commit**

```bash
git add app/models/node.rb app/controllers/nodes_controller.rb \
  app/views/nodes/
git commit -m "feat(bmc): add per-node BMC credential form"
```

---

## Task 6: Salt Runner Module — `qis_bmc.py`

**Files:**
- Create: `salt/runners/qis_bmc.py`
- Create: `salt/runners/tests/test_qis_bmc.py` (unit tests)

**Step 1: Write unit tests for the runner**

```python
# salt/runners/tests/test_qis_bmc.py
"""Tests for qis_bmc Salt runner module."""

import unittest
from unittest.mock import patch, MagicMock
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import qis_bmc


class TestProtocolDetection(unittest.TestCase):
    """Test BMC protocol auto-detection logic."""

    @patch("qis_bmc.requests.get")
    def test_detects_redfish_when_available(self, mock_get):
        mock_get.return_value = MagicMock(status_code=200)
        result = qis_bmc._detect_protocol("10.0.0.1", "admin", "pass", True)
        self.assertEqual(result, "redfish")

    @patch("qis_bmc.subprocess.run")
    @patch("qis_bmc.requests.get", side_effect=Exception("Connection refused"))
    def test_falls_back_to_ipmi(self, mock_get, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout="Device ID : 32")
        result = qis_bmc._detect_protocol("10.0.0.1", "admin", "pass", True)
        self.assertEqual(result, "ipmi")

    @patch("qis_bmc.subprocess.run")
    @patch("qis_bmc.requests.get", side_effect=Exception("Connection refused"))
    def test_returns_none_when_both_fail(self, mock_get, mock_run):
        mock_run.return_value = MagicMock(returncode=1, stderr="Error")
        result = qis_bmc._detect_protocol("10.0.0.1", "admin", "pass", True)
        self.assertIsNone(result)


class TestSensorParsing(unittest.TestCase):
    """Test IPMI SDR output parsing."""

    def test_parses_temperature_sdr(self):
        sdr_output = (
            "CPU1 Temp        | 52 degrees C      | ok\n"
            "Inlet Temp       | 24 degrees C      | ok\n"
            "FAN1             | 4200 RPM          | ok\n"
            "Total Power      | 450 Watts         | ok\n"
        )
        readings = qis_bmc._parse_ipmi_sdr(sdr_output)
        temps = [r for r in readings if r["type"] == "temperature"]
        fans = [r for r in readings if r["type"] == "fan"]
        power = [r for r in readings if r["type"] == "power"]
        self.assertEqual(len(temps), 2)
        self.assertEqual(temps[0]["value"], 52.0)
        self.assertEqual(len(fans), 1)
        self.assertEqual(fans[0]["value"], 4200.0)
        self.assertEqual(len(power), 1)


if __name__ == "__main__":
    unittest.main()
```

**Step 2: Run tests to verify they fail**

Run: `cd salt/runners && python -m pytest tests/test_qis_bmc.py -v`
Expected: FAIL — module not found

**Step 3: Write the Salt runner module**

```python
# salt/runners/qis_bmc.py
"""
QIS BMC Out-of-Band Management Runner

Runs on the Salt master to collect sensor data and hardware inventory
from BMCs via Redfish and IPMI protocols.

Usage:
    salt-run qis_bmc.collect_sensors
    salt-run qis_bmc.collect_sensors node=compute-001
    salt-run qis_bmc.collect_inventory node=compute-001
    salt-run qis_bmc.check_connectivity
"""

import json
import logging
import re
import subprocess
import time

try:
    import requests
except ImportError:
    requests = None

log = logging.getLogger(__name__)

# Protocol cache: {bmc_address: "redfish"|"ipmi"}
_protocol_cache = {}


def collect_sensors(node=None):
    """
    Collect sensor readings from BMCs.

    Args:
        node: Optional hostname to collect from a single node.
              If None, collects from all configured nodes.

    Returns:
        dict: Summary of collection results.
    """
    credentials = _fetch_credentials()
    if not credentials:
        return {"success": False, "error": "No BMC credentials configured"}

    if node:
        credentials = [c for c in credentials if c.get("hostname") == node]

    results = []
    errors = []

    for cred in credentials:
        try:
            protocol = _resolve_protocol(cred)
            if not protocol:
                errors.append({"node": cred["hostname"], "error": "Unreachable"})
                continue

            if protocol == "redfish":
                readings = _collect_sensors_redfish(cred)
            else:
                readings = _collect_sensors_ipmi(cred)

            result = {
                "node_hostname": cred["hostname"],
                "node_id": cred["node_id"],
                "protocol": protocol,
                "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "readings": readings,
            }
            results.append(result)
        except Exception as exc:
            log.error("Failed to collect sensors for %s: %s", cred["hostname"], exc)
            errors.append({"node": cred["hostname"], "error": str(exc)})

    # Fire event with results
    if results:
        __salt__["event.send"](
            tag="qis/bmc/sensors",
            data={"results": results, "errors": errors},
        )

    return {
        "success": True,
        "collected": len(results),
        "failed": len(errors),
        "errors": errors,
    }


def collect_inventory(node=None):
    """
    Collect hardware inventory from BMCs.

    Args:
        node: Optional hostname to collect from a single node.

    Returns:
        dict: Summary of collection results.
    """
    credentials = _fetch_credentials()
    if not credentials:
        return {"success": False, "error": "No BMC credentials configured"}

    if node:
        credentials = [c for c in credentials if c.get("hostname") == node]

    results = []
    errors = []

    for cred in credentials:
        try:
            protocol = _resolve_protocol(cred)
            if not protocol:
                errors.append({"node": cred["hostname"], "error": "Unreachable"})
                continue

            if protocol == "redfish":
                inventory = _collect_inventory_redfish(cred)
            else:
                inventory = _collect_inventory_ipmi(cred)

            result = {
                "node_hostname": cred["hostname"],
                "node_id": cred["node_id"],
                "protocol": protocol,
                "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "inventory": inventory,
            }
            results.append(result)
        except Exception as exc:
            log.error("Failed to collect inventory for %s: %s", cred["hostname"], exc)
            errors.append({"node": cred["hostname"], "error": str(exc)})

    if results:
        __salt__["event.send"](
            tag="qis/bmc/inventory",
            data={"results": results, "errors": errors},
        )

    return {
        "success": True,
        "collected": len(results),
        "failed": len(errors),
        "errors": errors,
    }


def check_connectivity(node=None):
    """
    Check BMC connectivity for configured nodes.

    Returns:
        dict: Per-node connectivity status.
    """
    credentials = _fetch_credentials()
    if not credentials:
        return {"success": False, "error": "No BMC credentials configured"}

    if node:
        credentials = [c for c in credentials if c.get("hostname") == node]

    statuses = []
    for cred in credentials:
        protocol = _detect_protocol(
            cred["bmc_address"], cred["username"], cred["password"],
            cred.get("verify_ssl", True)
        )
        statuses.append({
            "node": cred["hostname"],
            "node_id": cred["node_id"],
            "bmc_address": cred["bmc_address"],
            "reachable": protocol is not None,
            "protocol": protocol,
        })

    return {"success": True, "statuses": statuses}


# --- Internal helpers ---


def _fetch_credentials():
    """Fetch BMC credentials from Rails API."""
    rails_url = __opts__.get("qis_rails_url", "http://localhost:3000")
    api_token = __opts__.get("qis_api_token", "")

    try:
        resp = requests.get(
            f"{rails_url}/api/v1/bmc/credentials",
            headers={"Authorization": f"Bearer {api_token}"},
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json().get("credentials", [])
    except Exception as exc:
        log.error("Failed to fetch BMC credentials from Rails: %s", exc)
        return []


def _resolve_protocol(cred):
    """Resolve protocol for a node, using cache and explicit setting."""
    bmc_addr = cred["bmc_address"]
    explicit = cred.get("protocol", "auto")

    if explicit in ("redfish", "ipmi"):
        return explicit

    if bmc_addr in _protocol_cache:
        return _protocol_cache[bmc_addr]

    detected = _detect_protocol(
        bmc_addr, cred["username"], cred["password"],
        cred.get("verify_ssl", True)
    )
    if detected:
        _protocol_cache[bmc_addr] = detected
    return detected


def _detect_protocol(address, username, password, verify_ssl):
    """Auto-detect: try Redfish first, then IPMI."""
    # Try Redfish
    if requests:
        try:
            resp = requests.get(
                f"https://{address}/redfish/v1/",
                auth=(username, password),
                verify=verify_ssl,
                timeout=5,
            )
            if resp.status_code == 200:
                return "redfish"
        except Exception:
            pass

    # Try IPMI
    try:
        result = subprocess.run(
            ["ipmitool", "-H", address, "-U", username, "-P", password, "mc", "info"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            return "ipmi"
    except Exception:
        pass

    return None


def _collect_sensors_redfish(cred):
    """Collect sensor readings via Redfish API."""
    base = f"https://{cred['bmc_address']}"
    auth = (cred["username"], cred["password"])
    verify = cred.get("verify_ssl", True)
    readings = []

    # Thermal sensors
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Chassis/1/Thermal",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            for temp in data.get("Temperatures", []):
                if temp.get("ReadingCelsius") is not None:
                    readings.append({
                        "type": "temperature",
                        "name": temp.get("Name", "unknown").lower().replace(" ", "_"),
                        "value": float(temp["ReadingCelsius"]),
                        "unit": "celsius",
                        "status": _redfish_health(temp.get("Status", {})),
                    })
            for fan in data.get("Fans", []):
                if fan.get("Reading") is not None:
                    unit = "percent" if fan.get("ReadingUnits") == "Percent" else "rpm"
                    readings.append({
                        "type": "fan",
                        "name": fan.get("Name", "unknown").lower().replace(" ", "_"),
                        "value": float(fan["Reading"]),
                        "unit": unit,
                        "status": _redfish_health(fan.get("Status", {})),
                    })
    except Exception as exc:
        log.warning("Redfish Thermal query failed: %s", exc)

    # Power sensors
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Chassis/1/Power",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            for psu in data.get("PowerControl", []):
                if psu.get("PowerConsumedWatts") is not None:
                    readings.append({
                        "type": "power",
                        "name": psu.get("Name", "total").lower().replace(" ", "_"),
                        "value": float(psu["PowerConsumedWatts"]),
                        "unit": "watts",
                        "status": _redfish_health(psu.get("Status", {})),
                    })
    except Exception as exc:
        log.warning("Redfish Power query failed: %s", exc)

    return readings


def _collect_sensors_ipmi(cred):
    """Collect sensor readings via ipmitool sdr."""
    result = subprocess.run(
        [
            "ipmitool", "-H", cred["bmc_address"],
            "-U", cred["username"], "-P", cred["password"],
            "sdr", "type", "Temperature", "Fan", "Current",
        ],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(f"ipmitool sdr failed: {result.stderr}")

    return _parse_ipmi_sdr(result.stdout)


def _parse_ipmi_sdr(output):
    """Parse ipmitool sdr output into structured readings."""
    readings = []
    for line in output.strip().split("\n"):
        if not line.strip():
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 3:
            continue

        name = parts[0].lower().replace(" ", "_")
        value_str = parts[1]
        status = "ok" if "ok" in parts[2].lower() else "warning"

        # Parse value and unit
        match = re.match(r"([\d.]+)\s*(degrees C|RPM|Watts|Percent)", value_str, re.IGNORECASE)
        if not match:
            continue

        value = float(match.group(1))
        raw_unit = match.group(2).lower()

        if "degrees" in raw_unit:
            sensor_type, unit = "temperature", "celsius"
        elif "rpm" in raw_unit:
            sensor_type, unit = "fan", "rpm"
        elif "watts" in raw_unit:
            sensor_type, unit = "power", "watts"
        elif "percent" in raw_unit:
            sensor_type, unit = "fan", "percent"
        else:
            continue

        readings.append({
            "type": sensor_type,
            "name": name,
            "value": value,
            "unit": unit,
            "status": status,
        })

    return readings


def _collect_inventory_redfish(cred):
    """Collect hardware inventory via Redfish API."""
    base = f"https://{cred['bmc_address']}"
    auth = (cred["username"], cred["password"])
    verify = cred.get("verify_ssl", True)
    inventory = {
        "processors": [], "memory": [], "storage": [],
        "network": [], "infiniband": [],
        "bios": {}, "bmc_info": {},
    }

    # Processors
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Systems/1/Processors",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            for member in resp.json().get("Members", []):
                proc_resp = requests.get(
                    f"{base}{member['@odata.id']}",
                    auth=auth, verify=verify, timeout=10,
                )
                if proc_resp.status_code == 200:
                    p = proc_resp.json()
                    inventory["processors"].append({
                        "socket": p.get("Socket", ""),
                        "model": p.get("Model", ""),
                        "cores_physical": p.get("TotalCores", 0),
                        "freq_base": p.get("MaxSpeedMHz", 0),
                        "freq_max": p.get("MaxSpeedMHz", 0),
                        "serial": p.get("SerialNumber", ""),
                        "architecture": p.get("InstructionSet", ""),
                    })
    except Exception as exc:
        log.warning("Redfish Processors query failed: %s", exc)

    # Memory
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Systems/1/Memory",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            for member in resp.json().get("Members", []):
                mem_resp = requests.get(
                    f"{base}{member['@odata.id']}",
                    auth=auth, verify=verify, timeout=10,
                )
                if mem_resp.status_code == 200:
                    m = mem_resp.json()
                    inventory["memory"].append({
                        "slot": m.get("DeviceLocator", ""),
                        "size_gb": m.get("CapacityMiB", 0) / 1024,
                        "speed_mhz": m.get("OperatingSpeedMhz", 0),
                        "manufacturer": m.get("Manufacturer", ""),
                        "serial": m.get("SerialNumber", ""),
                        "type": m.get("MemoryDeviceType", ""),
                    })
    except Exception as exc:
        log.warning("Redfish Memory query failed: %s", exc)

    # BIOS
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Systems/1/Bios",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            b = resp.json()
            inventory["bios"] = {
                "vendor": b.get("Attributes", {}).get("SystemManufacturer", ""),
                "version": b.get("BiosVersion", b.get("Id", "")),
                "release_date": b.get("Attributes", {}).get("SystemBiosReleaseDate", ""),
            }
    except Exception as exc:
        log.warning("Redfish BIOS query failed: %s", exc)

    # BMC Info
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Managers/1",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            mgr = resp.json()
            inventory["bmc_info"] = {
                "model": mgr.get("Model", ""),
                "firmware": mgr.get("FirmwareVersion", ""),
                "ip": cred["bmc_address"],
            }
    except Exception as exc:
        log.warning("Redfish Manager query failed: %s", exc)

    return inventory


def _collect_inventory_ipmi(cred):
    """Collect hardware inventory via ipmitool."""
    inventory = {
        "processors": [], "memory": [], "storage": [],
        "network": [], "infiniband": [],
        "bios": {}, "bmc_info": {},
    }
    base_cmd = [
        "ipmitool", "-H", cred["bmc_address"],
        "-U", cred["username"], "-P", cred["password"],
    ]

    # FRU data
    try:
        result = subprocess.run(
            base_cmd + ["fru", "print"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            fru = _parse_ipmi_fru(result.stdout)
            inventory["bios"] = {
                "vendor": fru.get("Board Mfg", ""),
                "version": fru.get("Product Version", ""),
                "release_date": fru.get("Board Mfg Date", ""),
            }
    except Exception as exc:
        log.warning("ipmitool fru failed: %s", exc)

    # BMC info
    try:
        result = subprocess.run(
            base_cmd + ["mc", "info"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            mc = _parse_ipmi_mc_info(result.stdout)
            inventory["bmc_info"] = {
                "model": mc.get("Device ID", ""),
                "firmware": mc.get("Firmware Revision", ""),
                "ip": cred["bmc_address"],
            }
    except Exception as exc:
        log.warning("ipmitool mc info failed: %s", exc)

    return inventory


def _parse_ipmi_fru(output):
    """Parse ipmitool fru print output into a dict."""
    result = {}
    for line in output.split("\n"):
        if ":" in line:
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip()
    return result


def _parse_ipmi_mc_info(output):
    """Parse ipmitool mc info output into a dict."""
    result = {}
    for line in output.split("\n"):
        if ":" in line:
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip()
    return result


def _redfish_health(status_obj):
    """Convert Redfish Status to simple status string."""
    health = status_obj.get("Health", "OK")
    return {"OK": "ok", "Warning": "warning", "Critical": "critical"}.get(health, "ok")
```

**Step 4: Run unit tests**

Run: `cd salt/runners && python -m pytest tests/test_qis_bmc.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add salt/runners/qis_bmc.py salt/runners/tests/test_qis_bmc.py
git commit -m "feat(bmc): add Salt runner module for BMC collection"
```

---

## Task 7: BMC Credentials API Endpoint

**Files:**
- Create: `app/controllers/api/v1/bmc/credentials_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/bmc/credentials_spec.rb`

**Step 1: Write the request spec**

```ruby
# spec/requests/api/v1/bmc/credentials_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Credentials", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }

  describe "GET /api/v1/bmc/credentials" do
    let!(:node1) { create(:node, hostname: "compute-001") }
    let!(:node2) { create(:node, hostname: "compute-002") }
    let!(:global) { create(:bmc_credential, :global_default, bmc_address: "default-bmc") }
    let!(:node1_cred) { create(:bmc_credential, node: node1, bmc_address: "10.0.0.1") }

    it "returns credentials for all nodes with BMC access" do
      get "/api/v1/bmc/credentials", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      creds = body["credentials"]
      # node1 has specific cred, node2 uses global default
      expect(creds.length).to be >= 1
      node1_entry = creds.find { |c| c["hostname"] == "compute-001" }
      expect(node1_entry["bmc_address"]).to eq("10.0.0.1")
    end

    it "requires authentication" do
      get "/api/v1/bmc/credentials"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/api/v1/bmc/credentials_spec.rb`
Expected: FAIL — route not found

**Step 3: Add route**

Add to `config/routes.rb` inside `namespace :api, namespace :v1`:
```ruby
namespace :bmc do
  get "credentials", to: "credentials#index"
end
```

**Step 4: Create controller**

```ruby
# app/controllers/api/v1/bmc/credentials_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class CredentialsController < Api::V1::BaseController
        def index
          global_default = BmcCredential.global_default
          nodes = Node.all
          credentials = []

          nodes.find_each do |node|
            cred = node.bmc_credential || global_default
            next unless cred

            credentials << {
              node_id: node.id,
              hostname: node.hostname,
              bmc_address: node.bmc_credential&.bmc_address || cred.bmc_address,
              username: cred.username,
              password: cred.password,
              protocol: cred.protocol,
              port: cred.port,
              verify_ssl: cred.verify_ssl
            }
          end

          render json: { credentials: credentials }
        end
      end
    end
  end
end
```

**Step 5: Run tests**

Run: `bin/rspec spec/requests/api/v1/bmc/credentials_spec.rb`
Expected: PASS

**Step 6: Commit**

```bash
git add app/controllers/api/v1/bmc/credentials_controller.rb \
  config/routes.rb spec/requests/api/v1/bmc/credentials_spec.rb
git commit -m "feat(bmc): add API endpoint for Salt runner credential retrieval"
```

---

## Task 8: Sensor Ingestion Service

**Files:**
- Create: `app/services/bmc/sensor_ingestion_service.rb`
- Create: `spec/services/bmc/sensor_ingestion_service_spec.rb`

**Step 1: Write the test**

```ruby
# spec/services/bmc/sensor_ingestion_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorIngestionService do
  let(:node) { create(:node) }

  let(:event_data) do
    {
      "results" => [
        {
          "node_id" => node.id,
          "node_hostname" => node.hostname,
          "protocol" => "redfish",
          "collected_at" => "2026-01-30T10:00:00Z",
          "readings" => [
            { "type" => "temperature", "name" => "cpu1", "value" => 52.0,
              "unit" => "celsius", "status" => "ok" },
            { "type" => "fan", "name" => "fan1", "value" => 4200,
              "unit" => "rpm", "status" => "ok" },
            { "type" => "power", "name" => "psu_total", "value" => 450,
              "unit" => "watts", "status" => "ok" }
          ]
        }
      ],
      "errors" => []
    }
  end

  describe "#call" do
    it "creates sensor readings for the node" do
      expect { described_class.new(event_data).call }
        .to change(BmcSensorReading, :count).by(3)
    end

    it "stores correct sensor values" do
      described_class.new(event_data).call
      temp = BmcSensorReading.find_by(node: node, sensor_type: "temperature")
      expect(temp.value).to eq(52.0)
      expect(temp.unit).to eq("celsius")
    end

    it "skips nodes that do not exist" do
      event_data["results"][0]["node_id"] = 99999
      expect { described_class.new(event_data).call }
        .not_to change(BmcSensorReading, :count)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/bmc/sensor_ingestion_service_spec.rb`
Expected: FAIL — class not found

**Step 3: Implement the service**

```ruby
# app/services/bmc/sensor_ingestion_service.rb
# frozen_string_literal: true

module Bmc
  class SensorIngestionService
    def initialize(event_data)
      @results = event_data["results"] || []
      @errors = event_data["errors"] || []
    end

    def call
      records = []

      @results.each do |result|
        node = Node.find_by(id: result["node_id"])
        next unless node

        collected_at = Time.zone.parse(result["collected_at"])

        result["readings"].each do |reading|
          records << {
            node_id: node.id,
            sensor_type: reading["type"],
            sensor_name: reading["name"],
            value: reading["value"].to_f,
            unit: reading["unit"],
            status: reading["status"],
            recorded_at: collected_at
          }
        end
      end

      BmcSensorReading.insert_all(records) if records.any?

      { inserted: records.size, errors: @errors }
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rspec spec/services/bmc/sensor_ingestion_service_spec.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/bmc/sensor_ingestion_service.rb \
  spec/services/bmc/sensor_ingestion_service_spec.rb
git commit -m "feat(bmc): add sensor ingestion service for Salt events"
```

---

## Task 9: Inventory Ingestion Service

**Files:**
- Create: `app/services/bmc/inventory_ingestion_service.rb`
- Create: `spec/services/bmc/inventory_ingestion_service_spec.rb`

**Step 1: Write the test**

```ruby
# spec/services/bmc/inventory_ingestion_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::InventoryIngestionService do
  let(:node) { create(:node) }

  let(:event_data) do
    {
      "results" => [
        {
          "node_id" => node.id,
          "node_hostname" => node.hostname,
          "protocol" => "redfish",
          "collected_at" => "2026-01-30T10:00:00Z",
          "inventory" => {
            "processors" => [{ "socket" => "CPU1", "model" => "Xeon", "cores_physical" => 32 }],
            "memory" => [{ "slot" => "DIMM_A1", "size_gb" => 64, "speed_mhz" => 3200 }],
            "storage" => [],
            "network" => [],
            "infiniband" => [],
            "bios" => { "vendor" => "AMI", "version" => "1.2.3" },
            "bmc_info" => { "model" => "iDRAC9", "firmware" => "6.10.00.00" }
          }
        }
      ],
      "errors" => []
    }
  end

  describe "#call" do
    it "creates a BmcInventory record" do
      expect { described_class.new(event_data).call }
        .to change(BmcInventory, :count).by(1)
    end

    it "stores processor data" do
      described_class.new(event_data).call
      inv = BmcInventory.last
      expect(inv.processors.first["model"]).to eq("Xeon")
      expect(inv.collection_method).to eq("redfish")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/bmc/inventory_ingestion_service_spec.rb`
Expected: FAIL

**Step 3: Implement the service**

```ruby
# app/services/bmc/inventory_ingestion_service.rb
# frozen_string_literal: true

module Bmc
  class InventoryIngestionService
    def initialize(event_data)
      @results = event_data["results"] || []
    end

    def call
      created = []

      @results.each do |result|
        node = Node.find_by(id: result["node_id"])
        next unless node

        inventory = node.bmc_inventories.create!(
          processors: result["inventory"]["processors"] || [],
          memory: result["inventory"]["memory"] || [],
          storage: result["inventory"]["storage"] || [],
          network: result["inventory"]["network"] || [],
          infiniband: result["inventory"]["infiniband"] || [],
          bios: result["inventory"]["bios"] || {},
          bmc_info: result["inventory"]["bmc_info"] || {},
          collection_method: result["protocol"],
          captured_at: Time.zone.parse(result["collected_at"])
        )
        created << inventory

        # Trigger reconciliation
        Bmc::ReconciliationService.new(node).call
      end

      { created: created.size }
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rspec spec/services/bmc/inventory_ingestion_service_spec.rb`
Expected: PASS (ReconciliationService may not exist yet — stub it if needed or allow the call to fail gracefully)

**Step 5: Commit**

```bash
git add app/services/bmc/inventory_ingestion_service.rb \
  spec/services/bmc/inventory_ingestion_service_spec.rb
git commit -m "feat(bmc): add inventory ingestion service for Salt events"
```

---

## Task 10: Reconciliation Service

**Files:**
- Create: `app/services/bmc/reconciliation_service.rb`
- Create: `spec/services/bmc/reconciliation_service_spec.rb`

**Step 1: Write the test**

```ruby
# spec/services/bmc/reconciliation_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::ReconciliationService do
  let(:node) { create(:node) }

  let!(:node_state) do
    create(:node_state, node: node, cpu_info: {
      "model" => "Xeon Gold 6248",
      "cores" => 20,
      "sockets" => 2
    })
  end

  let!(:bmc_inventory) do
    create(:bmc_inventory, node: node, processors: [
      { "model" => "Xeon Gold 6248", "cores_physical" => 20, "serial" => "SN123" },
      { "model" => "Xeon Gold 6248", "cores_physical" => 20, "serial" => "SN456" }
    ])
  end

  describe "#call" do
    context "when data matches" do
      it "does not create discrepancies" do
        expect { described_class.new(node).call }
          .not_to change(InventoryDiscrepancy, :count)
      end
    end

    context "when core count differs" do
      before do
        bmc_inventory.update!(processors: [
          { "model" => "Xeon Gold 6248", "cores_physical" => 24, "serial" => "SN123" }
        ])
      end

      it "creates a discrepancy" do
        expect { described_class.new(node).call }
          .to change(InventoryDiscrepancy, :count).by_at_least(1)
      end
    end

    context "when previous discrepancy is resolved" do
      let!(:old_discrepancy) do
        create(:inventory_discrepancy, node: node, field_path: "processors.0.cores_physical")
      end

      it "auto-resolves discrepancies that no longer exist" do
        described_class.new(node).call
        expect(old_discrepancy.reload).to be_resolved
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/bmc/reconciliation_service_spec.rb`
Expected: FAIL

**Step 3: Implement the service**

```ruby
# app/services/bmc/reconciliation_service.rb
# frozen_string_literal: true

module Bmc
  class ReconciliationService
    SEVERITY_MAP = {
      "serial" => :critical,
      "cores_physical" => :critical,
      "cores" => :critical,
      "model" => :warning,
      "version" => :warning,
      "speed_mhz" => :warning,
      "size_gb" => :warning
    }.freeze

    def initialize(node)
      @node = node
    end

    def call
      latest_bmc = @node.bmc_inventories.order(captured_at: :desc).first
      latest_state = @node.node_states.order(created_at: :desc).first

      return { compared: false, reason: "missing data" } unless latest_bmc && latest_state

      current_discrepancies = compare(latest_state, latest_bmc)

      # Auto-resolve discrepancies that no longer exist
      existing = @node.inventory_discrepancies.unresolved
      existing.each do |disc|
        unless current_discrepancies.any? { |d| d[:field_path] == disc.field_path }
          disc.resolve!(note: "Auto-resolved: values now match")
        end
      end

      # Create new discrepancies
      current_discrepancies.each do |disc|
        next if @node.inventory_discrepancies.unresolved.exists?(field_path: disc[:field_path])

        @node.inventory_discrepancies.create!(disc)
      end

      { compared: true, discrepancies: current_discrepancies.size }
    end

    private

    def compare(state, bmc)
      discrepancies = []
      # Compare processor core counts (example comparison)
      # The specific comparisons depend on how NodeState stores data vs BmcInventory
      # This is a framework — extend with specific field comparisons as needed
      discrepancies
    end

    def severity_for(field_name)
      SEVERITY_MAP.fetch(field_name, :info)
    end
  end
end
```

Note: The `compare` method is a framework. The specific field comparisons depend on the exact structure of `NodeState` data vs `BmcInventory` data. Implement concrete comparisons based on the actual data shapes during implementation.

**Step 4: Run tests**

Run: `bin/rspec spec/services/bmc/reconciliation_service_spec.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/bmc/reconciliation_service.rb \
  spec/services/bmc/reconciliation_service_spec.rb
git commit -m "feat(bmc): add reconciliation service for in-band vs OOB comparison"
```

---

## Task 11: Salt Trigger Service and Event Listener Extension

**Files:**
- Create: `app/services/bmc/salt_trigger_service.rb`
- Create: `spec/services/bmc/salt_trigger_service_spec.rb`
- Modify: `app/services/salt/event_listener_service.rb` (add BMC event handlers)
- Modify: `app/services/salt_api_client.rb` (add `run_runner_async` if not present)

**Step 1: Write the trigger service test**

```ruby
# spec/services/bmc/salt_trigger_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SaltTriggerService do
  let(:salt_client) { instance_double(SaltApiClient) }

  before do
    allow(SaltApiClient).to receive(:new).and_return(salt_client)
  end

  describe "#collect_sensors" do
    it "calls Salt runner_async for sensor collection" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.collect_sensors", kwarg: {})
        .and_return({ "success" => true })

      result = described_class.new.collect_sensors
      expect(result["success"]).to be true
    end

    it "passes node filter when specified" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.collect_sensors", kwarg: { node: "compute-001" })
        .and_return({ "success" => true })

      described_class.new.collect_sensors(node: "compute-001")
    end
  end

  describe "#collect_inventory" do
    it "calls Salt runner for inventory collection" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.collect_inventory", kwarg: {})
        .and_return({ "success" => true })

      described_class.new.collect_inventory
    end
  end

  describe "#check_connectivity" do
    it "calls Salt runner for connectivity check" do
      expect(salt_client).to receive(:run_runner)
        .with("qis_bmc.check_connectivity", kwarg: {})
        .and_return({ "success" => true, "statuses" => [] })

      described_class.new.check_connectivity
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/bmc/salt_trigger_service_spec.rb`
Expected: FAIL

**Step 3: Implement the trigger service**

```ruby
# app/services/bmc/salt_trigger_service.rb
# frozen_string_literal: true

module Bmc
  class SaltTriggerService
    def initialize
      @client = SaltApiClient.new
    end

    def collect_sensors(node: nil)
      kwargs = {}
      kwargs[:node] = node if node
      @client.run_runner("qis_bmc.collect_sensors", kwarg: kwargs)
    end

    def collect_inventory(node: nil)
      kwargs = {}
      kwargs[:node] = node if node
      @client.run_runner("qis_bmc.collect_inventory", kwarg: kwargs)
    end

    def check_connectivity(node: nil)
      kwargs = {}
      kwargs[:node] = node if node
      @client.run_runner("qis_bmc.check_connectivity", kwarg: kwargs)
    end
  end
end
```

**Step 4: Extend EventListenerService**

Add BMC event handling to `app/services/salt/event_listener_service.rb`. In the `dispatch_event` method, add:

```ruby
when /\Aqis\/bmc\/sensors\z/
  handle_bmc_sensors(data)
when /\Aqis\/bmc\/inventory\z/
  handle_bmc_inventory(data)
```

Add the handler methods:

```ruby
def handle_bmc_sensors(data)
  Bmc::SensorIngestionService.new(data).call
rescue => e
  Rails.logger.error("BMC sensor ingestion failed: #{e.message}")
end

def handle_bmc_inventory(data)
  Bmc::InventoryIngestionService.new(data).call
rescue => e
  Rails.logger.error("BMC inventory ingestion failed: #{e.message}")
end
```

**Step 5: Run tests**

Run: `bin/rspec spec/services/bmc/salt_trigger_service_spec.rb`
Expected: PASS

**Step 6: Commit**

```bash
git add app/services/bmc/salt_trigger_service.rb \
  spec/services/bmc/salt_trigger_service_spec.rb \
  app/services/salt/event_listener_service.rb
git commit -m "feat(bmc): add Salt trigger service and BMC event handlers"
```

---

## Task 12: Sensor Query Service

**Files:**
- Create: `app/services/bmc/sensor_query_service.rb`
- Create: `spec/services/bmc/sensor_query_service_spec.rb`

**Step 1: Write the test**

```ruby
# spec/services/bmc/sensor_query_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorQueryService do
  let(:node) { create(:node) }

  before do
    # Insert test readings
    readings = (1..24).map do |hour|
      { node_id: node.id, sensor_type: "temperature", sensor_name: "cpu1",
        value: 50.0 + rand(10), unit: "celsius", status: "ok",
        recorded_at: hour.hours.ago }
    end
    BmcSensorReading.insert_all(readings)
  end

  describe "#chart_data" do
    it "returns data grouped by sensor name" do
      service = described_class.new(node, sensor_type: "temperature", range: "24h")
      data = service.chart_data
      expect(data).to be_a(Array)
      expect(data.first[:name]).to eq("cpu1")
      expect(data.first[:data].length).to eq(24)
    end
  end

  describe "#current_readings" do
    it "returns the latest reading per sensor" do
      service = described_class.new(node, sensor_type: "temperature")
      readings = service.current_readings
      expect(readings.length).to eq(1)
      expect(readings.first.sensor_name).to eq("cpu1")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/bmc/sensor_query_service_spec.rb`
Expected: FAIL

**Step 3: Implement the service**

```ruby
# app/services/bmc/sensor_query_service.rb
# frozen_string_literal: true

module Bmc
  class SensorQueryService
    RANGES = {
      "24h" => 24.hours,
      "7d" => 7.days,
      "30d" => 30.days,
      "90d" => 90.days
    }.freeze

    def initialize(node, sensor_type: nil, range: "24h")
      @node = node
      @sensor_type = sensor_type
      @range = RANGES.fetch(range, 24.hours)
    end

    def chart_data
      readings = BmcSensorReading
        .for_node(@node.id)
        .since(@range.ago)

      readings = readings.of_type(@sensor_type) if @sensor_type

      readings
        .group_by(&:sensor_name)
        .map do |name, records|
          {
            name: name,
            data: records.sort_by(&:recorded_at).map { |r| [r.recorded_at, r.value] }
          }
        end
    end

    def current_readings
      subquery = BmcSensorReading
        .for_node(@node.id)
        .select("DISTINCT ON (sensor_type, sensor_name) *")
        .order(:sensor_type, :sensor_name, recorded_at: :desc)

      records = BmcSensorReading.from(subquery, :bmc_sensor_readings)

      records = records.where(sensor_type: @sensor_type) if @sensor_type
      records.to_a
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rspec spec/services/bmc/sensor_query_service_spec.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/bmc/sensor_query_service.rb \
  spec/services/bmc/sensor_query_service_spec.rb
git commit -m "feat(bmc): add sensor query service for chart data"
```

---

## Task 13: TimescaleDB Continuous Aggregate and Retention Policies

**Files:**
- Create: `db/migrate/TIMESTAMP_add_timescaledb_policies.rb`

**Step 1: Create the migration**

```ruby
# db/migrate/TIMESTAMP_add_timescaledb_policies.rb
class AddTimescaledbPolicies < ActiveRecord::Migration[7.2]
  def up
    # Continuous aggregate for hourly averages
    execute <<~SQL
      CREATE MATERIALIZED VIEW bmc_sensor_readings_hourly
      WITH (timescaledb.continuous) AS
      SELECT
        node_id,
        sensor_type,
        sensor_name,
        time_bucket('1 hour', recorded_at) AS bucket,
        AVG(value) AS avg_value,
        MIN(value) AS min_value,
        MAX(value) AS max_value,
        unit
      FROM bmc_sensor_readings
      GROUP BY node_id, sensor_type, sensor_name, time_bucket('1 hour', recorded_at), unit;
    SQL

    # Refresh policy: update hourly aggregate every hour
    execute <<~SQL
      SELECT add_continuous_aggregate_policy('bmc_sensor_readings_hourly',
        start_offset => INTERVAL '2 hours',
        end_offset => INTERVAL '1 hour',
        schedule_interval => INTERVAL '1 hour');
    SQL

    # Retention policy: drop raw data older than 7 days
    execute "SELECT add_retention_policy('bmc_sensor_readings', INTERVAL '7 days');"

    # Retention policy: drop hourly aggregates older than 90 days
    execute "SELECT add_retention_policy('bmc_sensor_readings_hourly', INTERVAL '90 days');"
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS bmc_sensor_readings_hourly CASCADE;"
    execute "SELECT remove_retention_policy('bmc_sensor_readings', if_exists => true);"
  end
end
```

**Step 2: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration completes successfully

**Step 3: Commit**

```bash
git add db/migrate/*timescaledb_policies* db/schema.rb
git commit -m "feat(bmc): add TimescaleDB continuous aggregate and retention policies"
```

---

## Task 14: BMC Collection Controller (UI Triggers)

**Files:**
- Create: `app/controllers/api/v1/bmc/collect_controller.rb`
- Create: `app/controllers/api/v1/bmc/connectivity_controller.rb`
- Create: `app/controllers/api/v1/bmc/sensors_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/bmc/collect_spec.rb`

**Step 1: Write the test**

```ruby
# spec/requests/api/v1/bmc/collect_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bmc::Collect", type: :request do
  let(:user) { create(:user, role: :admin) }

  before { sign_in user }

  describe "POST /api/v1/bmc/collect/sensors" do
    it "triggers sensor collection via Salt" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_sensors)
        .and_return({ "success" => true, "collected" => 5 })

      post "/api/v1/bmc/collect/sensors"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be true
    end

    it "accepts optional node parameter" do
      trigger = instance_double(Bmc::SaltTriggerService)
      allow(Bmc::SaltTriggerService).to receive(:new).and_return(trigger)
      expect(trigger).to receive(:collect_sensors).with(node: "compute-001")
        .and_return({ "success" => true })

      post "/api/v1/bmc/collect/sensors", params: { node: "compute-001" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/bmc/collect/inventory" do
    it "triggers inventory collection via Salt" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_inventory)
        .and_return({ "success" => true, "collected" => 5 })

      post "/api/v1/bmc/collect/inventory"
      expect(response).to have_http_status(:ok)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/api/v1/bmc/collect_spec.rb`
Expected: FAIL

**Step 3: Add routes**

Add inside `namespace :bmc`:
```ruby
post "collect/sensors", to: "collect#sensors"
post "collect/inventory", to: "collect#inventory"
post "check_connectivity", to: "connectivity#check"
get "sensors/:node_id", to: "sensors#show"
```

**Step 4: Create controllers**

```ruby
# app/controllers/api/v1/bmc/collect_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class CollectController < ApplicationController
        before_action :authenticate_user!

        def sensors
          result = Bmc::SaltTriggerService.new.collect_sensors(node: params[:node])
          render json: result
        end

        def inventory
          result = Bmc::SaltTriggerService.new.collect_inventory(node: params[:node])
          render json: result
        end
      end
    end
  end
end
```

```ruby
# app/controllers/api/v1/bmc/connectivity_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class ConnectivityController < ApplicationController
        before_action :authenticate_user!

        def check
          result = Bmc::SaltTriggerService.new.check_connectivity(node: params[:node])
          render json: result
        end
      end
    end
  end
end
```

```ruby
# app/controllers/api/v1/bmc/sensors_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Bmc
      class SensorsController < ApplicationController
        before_action :authenticate_user!

        def show
          node = Node.find(params[:node_id])
          service = Bmc::SensorQueryService.new(
            node,
            sensor_type: params[:sensor_type],
            range: params[:range] || "24h"
          )

          render json: {
            chart_data: service.chart_data,
            current_readings: service.current_readings
          }
        end
      end
    end
  end
end
```

**Step 5: Run tests**

Run: `bin/rspec spec/requests/api/v1/bmc/collect_spec.rb`
Expected: PASS

**Step 6: Commit**

```bash
git add app/controllers/api/v1/bmc/ config/routes.rb \
  spec/requests/api/v1/bmc/
git commit -m "feat(bmc): add BMC collection and sensor API controllers"
```

---

## Task 15: BMC Status Card UI Component

**Files:**
- Create: `app/views/nodes/_bmc_status_card.html.erb`
- Modify: `app/views/nodes/show.html.erb` (render the card)
- Create: `app/controllers/nodes/bmc_controller.rb` (for Turbo actions)

**Step 1: Create the partial**

Create `app/views/nodes/_bmc_status_card.html.erb` that shows:
- BMC connection status (connected/unreachable/not configured) with colored badge
- Protocol (Redfish/IPMI)
- Last sensor collection time
- Last inventory collection time
- Unresolved discrepancy count with badge
- "Collect Sensors" button (Turbo method: :post to `/api/v1/bmc/collect/sensors?node=hostname`)
- "Collect Inventory" button (Turbo method: :post to `/api/v1/bmc/collect/inventory?node=hostname`)

Follow existing card component patterns in the codebase. Reference the node detail page layout for placement.

**Step 2: Add to node show page**

Render `<%= render "nodes/bmc_status_card", node: @node %>` in the appropriate location on the node detail page.

**Step 3: Verify it renders**

Run: `bin/dev` and navigate to a node detail page.
Expected: BMC status card appears (may show "Not Configured" if no credential exists)

**Step 4: Commit**

```bash
git add app/views/nodes/_bmc_status_card.html.erb app/views/nodes/show.html.erb
git commit -m "feat(bmc): add BMC status card to node detail page"
```

---

## Task 16: Sensor Charts UI

**Files:**
- Create: `app/views/nodes/_bmc_sensor_charts.html.erb`
- Create: `app/javascript/controllers/bmc_chart_controller.js` (Stimulus)
- Modify: `app/views/nodes/show.html.erb` (render charts section)

**Step 1: Create the Stimulus controller**

```javascript
// app/javascript/controllers/bmc_chart_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]
  static values = {
    nodeId: Number,
    sensorType: String,
    range: { type: String, default: "24h" }
  }

  connect() {
    this.loadChartData()
  }

  changeRange(event) {
    this.rangeValue = event.target.value
    this.loadChartData()
  }

  async loadChartData() {
    const url = `/api/v1/bmc/sensors/${this.nodeIdValue}?sensor_type=${this.sensorTypeValue}&range=${this.rangeValue}`
    const response = await fetch(url, {
      headers: { "Accept": "application/json" }
    })
    const data = await response.json()
    this.renderChart(data.chart_data)
  }

  renderChart(chartData) {
    // Chartkick renders via data attributes — update the container
    // This integrates with Chartkick's JavaScript API
  }
}
```

**Step 2: Create the charts partial**

Create `app/views/nodes/_bmc_sensor_charts.html.erb` with:
- Time range selector (24h / 7d / 30d / 90d) buttons
- Temperature line chart using `<%= line_chart ... %>` from Chartkick
- Fan speed line chart
- Power consumption area chart using `<%= area_chart ... %>`
- Current readings grid showing latest values with status colors

Use Chartkick helpers with data from `Bmc::SensorQueryService`.

**Step 3: Add to node show page**

Render the charts partial in the appropriate section.

**Step 4: Verify rendering**

Run: `bin/dev` and check the node detail page.
Expected: Chart sections render (empty if no data)

**Step 5: Commit**

```bash
git add app/views/nodes/_bmc_sensor_charts.html.erb \
  app/javascript/controllers/bmc_chart_controller.js \
  app/views/nodes/show.html.erb
git commit -m "feat(bmc): add sensor charts to node detail page"
```

---

## Task 17: BMC Inventory Tables UI

**Files:**
- Create: `app/views/nodes/_bmc_inventory_tables.html.erb`
- Modify: `app/views/nodes/show.html.erb`

**Step 1: Create the inventory tables partial**

Create `app/views/nodes/_bmc_inventory_tables.html.erb` with:
- Tabbed interface (use Stimulus or Turbo Frames for tab switching)
- Tabs: Processors / Memory / Storage / Network / InfiniBand / BIOS / BMC Info
- Each tab contains a data table rendering the JSONB data from the latest `BmcInventory`
- "Last collected" timestamp
- "Collect Inventory" button

Follow existing table patterns in the codebase.

**Step 2: Add to node show page**

Render the partial below the sensor charts section.

**Step 3: Verify rendering**

Run: `bin/dev` and navigate to a node page.
Expected: Tabbed inventory section appears (empty tables if no BMC inventory exists)

**Step 4: Commit**

```bash
git add app/views/nodes/_bmc_inventory_tables.html.erb app/views/nodes/show.html.erb
git commit -m "feat(bmc): add BMC inventory tables to node detail page"
```

---

## Task 18: Discrepancy Panel UI

**Files:**
- Create: `app/views/nodes/_discrepancy_panel.html.erb`
- Create: `app/controllers/nodes/discrepancies_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/nodes/show.html.erb`
- Create: `spec/requests/nodes/discrepancies_spec.rb`

**Step 1: Write the test**

```ruby
# spec/requests/nodes/discrepancies_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::Discrepancies", type: :request do
  let(:user) { create(:user, role: :admin) }
  let(:node) { create(:node) }
  let!(:discrepancy) { create(:inventory_discrepancy, node: node) }

  before { sign_in user }

  describe "PATCH /nodes/:node_id/discrepancies/:id/resolve" do
    it "resolves the discrepancy" do
      patch resolve_node_discrepancy_path(node, discrepancy), params: {
        resolution_note: "Verified correct in person"
      }
      expect(discrepancy.reload).to be_resolved
      expect(discrepancy.resolution_note).to eq("Verified correct in person")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/nodes/discrepancies_spec.rb`
Expected: FAIL

**Step 3: Add route and controller**

Add to `config/routes.rb` inside `resources :nodes`:
```ruby
resources :discrepancies, only: [], controller: "nodes/discrepancies" do
  member do
    patch :resolve
  end
end
```

```ruby
# app/controllers/nodes/discrepancies_controller.rb
# frozen_string_literal: true

module Nodes
  class DiscrepanciesController < ApplicationController
    before_action :authenticate_user!

    def resolve
      node = Node.find(params[:node_id])
      discrepancy = node.inventory_discrepancies.find(params[:id])
      discrepancy.resolve!(note: params[:resolution_note])

      redirect_to node_path(node), notice: "Discrepancy resolved."
    end
  end
end
```

**Step 4: Create the panel partial**

Create `app/views/nodes/_discrepancy_panel.html.erb`:
- Table showing field_path, inband_value, bmc_value, severity badge (green/amber/red)
- "Resolve" button per row — opens a small form for resolution_note
- Filter toggle: show all / unresolved only
- Empty state when no discrepancies

**Step 5: Add to node show page**

Render after the inventory tables section.

**Step 6: Run tests**

Run: `bin/rspec spec/requests/nodes/discrepancies_spec.rb`
Expected: PASS

**Step 7: Commit**

```bash
git add app/views/nodes/_discrepancy_panel.html.erb \
  app/controllers/nodes/discrepancies_controller.rb \
  config/routes.rb spec/requests/nodes/discrepancies_spec.rb \
  app/views/nodes/show.html.erb
git commit -m "feat(bmc): add discrepancy panel with resolution workflow"
```

---

## Task 19: Node List BMC Status Indicators

**Files:**
- Modify: `app/views/nodes/index.html.erb` (or relevant node list partial)

**Step 1: Add BMC status indicators**

In the node list table/cards, add:
- A small colored dot indicating BMC status:
  - Green: connected (has recent sensor readings within last collection interval)
  - Amber: configured but no recent data
  - Red: configured but unreachable (last connectivity check failed)
  - Gray: not configured (no BMC credential)
- Unresolved discrepancy count badge (if > 0)

Determine status from:
```ruby
# In a helper or presenter
def bmc_status_for(node)
  return :not_configured unless BmcCredential.for_node(node)
  latest = node.bmc_sensor_readings.order(recorded_at: :desc).first
  return :no_data unless latest
  return :stale if latest.recorded_at < 10.minutes.ago
  :connected
end
```

**Step 2: Verify rendering**

Run: `bin/dev` and check the nodes index page.
Expected: Gray dots for nodes without BMC credentials

**Step 3: Commit**

```bash
git add app/views/nodes/
git commit -m "feat(bmc): add BMC status dots and discrepancy badges to node list"
```

---

## Task 20: Settings Page — Collection Interval Configuration

**Files:**
- Modify: `app/views/settings/bmc_credentials/show.html.erb` (add interval setting)
- Modify: `app/controllers/settings/bmc_credentials_controller.rb` (handle interval)
- Create: `db/migrate/TIMESTAMP_add_bmc_settings_to_site_or_config.rb` (store interval)

The collection interval is stored as a global setting. Use an existing settings mechanism (if one exists) or add a `bmc_collection_interval` column to an appropriate settings table. This value is read by the `Bmc::SensorCollectionJob` to determine how frequently to trigger collection.

**Step 1: Add interval selector to BMC settings page**

Add a select field for collection interval: 1 min / 3 min / 5 min / 10 min / 15 min.

**Step 2: Store the setting**

Either add to an existing settings model or create a simple key-value store.

**Step 3: Commit**

```bash
git add app/views/settings/bmc_credentials/ \
  app/controllers/settings/bmc_credentials_controller.rb \
  db/migrate/*bmc_settings*
git commit -m "feat(bmc): add collection interval configuration to settings"
```

---

## Task 21: Sensor Collection Job (Scheduled Collection)

**Files:**
- Create: `app/jobs/bmc/sensor_collection_job.rb`
- Create: `spec/jobs/bmc/sensor_collection_job_spec.rb`

**Step 1: Write the test**

```ruby
# spec/jobs/bmc/sensor_collection_job_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorCollectionJob, type: :job do
  describe "#perform" do
    it "triggers sensor collection via Salt" do
      trigger = instance_double(Bmc::SaltTriggerService)
      allow(Bmc::SaltTriggerService).to receive(:new).and_return(trigger)
      expect(trigger).to receive(:collect_sensors)
        .and_return({ "success" => true })

      described_class.perform_now
    end

    it "re-enqueues itself based on configured interval" do
      allow_any_instance_of(Bmc::SaltTriggerService)
        .to receive(:collect_sensors)
        .and_return({ "success" => true })

      expect {
        described_class.perform_now
      }.to have_enqueued_job(described_class)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/jobs/bmc/sensor_collection_job_spec.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/bmc/sensor_collection_job.rb
# frozen_string_literal: true

module Bmc
  class SensorCollectionJob < ApplicationJob
    queue_as :default

    def perform
      result = Bmc::SaltTriggerService.new.collect_sensors
      Rails.logger.info("BMC sensor collection: #{result}")

      # Re-enqueue with configured interval
      interval = bmc_collection_interval
      self.class.set(wait: interval.minutes).perform_later if interval.positive?
    end

    private

    def bmc_collection_interval
      # Read from settings — adjust based on where the interval is stored
      5 # default 5 minutes
    end
  end
end
```

Note: The re-enqueue pattern is a simple approach. For production, consider using a proper recurring job framework (SolidQueue, whenever, etc.) when the project adds a job backend.

**Step 4: Run tests**

Run: `bin/rspec spec/jobs/bmc/sensor_collection_job_spec.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/jobs/bmc/sensor_collection_job.rb \
  spec/jobs/bmc/sensor_collection_job_spec.rb
git commit -m "feat(bmc): add recurring sensor collection job"
```

---

## Task 22: Final Integration — Wiring and Quality Gates

**Step 1: Run full test suite**

Run: `bin/rspec`
Expected: All tests pass

**Step 2: Run linter**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 3: Run security scan**

Run: `bin/brakeman`
Expected: No new warnings

**Step 4: Test Salt runner module**

Run: `cd salt/runners && python -m pytest tests/ -v`
Expected: All Python tests pass

**Step 5: Manual smoke test**

1. Start dev server: `bin/dev`
2. Navigate to Settings → BMC Credentials
3. Configure a global default credential
4. Navigate to a node → edit → add BMC credential
5. Verify BMC status card appears on node detail page
6. Verify sensor charts section renders (empty)
7. Verify inventory tables render (empty)
8. Verify discrepancy panel renders (empty state)
9. Verify node list shows gray BMC status dots

**Step 6: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "feat(bmc): final integration and cleanup"
```

---

## Summary

| Task | Component | Files Created/Modified |
|------|-----------|----------------------|
| 1 | TimescaleDB hypertable | 3 created, 1 modified |
| 2 | BMC model enhancements | 4 modified, 6 created |
| 3 | Chartkick dependency | 3 modified |
| 4 | Settings page (credentials) | 3 created, 2 modified |
| 5 | Per-node credential form | 3 modified |
| 6 | Salt runner module | 2 created |
| 7 | Credentials API endpoint | 2 created, 1 modified |
| 8 | Sensor ingestion service | 2 created |
| 9 | Inventory ingestion service | 2 created |
| 10 | Reconciliation service | 2 created |
| 11 | Salt trigger + event listener | 2 created, 2 modified |
| 12 | Sensor query service | 2 created |
| 13 | TimescaleDB policies | 1 created |
| 14 | Collection API controllers | 3 created, 1 modified |
| 15 | BMC status card UI | 1 created, 1 modified |
| 16 | Sensor charts UI | 2 created, 1 modified |
| 17 | Inventory tables UI | 1 created, 1 modified |
| 18 | Discrepancy panel UI | 2 created, 2 modified |
| 19 | Node list enhancements | 1 modified |
| 20 | Collection interval setting | 2 modified, 1 created |
| 21 | Sensor collection job | 2 created |
| 22 | Integration and QA | 0 (testing only) |
