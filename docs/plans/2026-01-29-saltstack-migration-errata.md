# SaltStack Migration — Plan Errata & Refinements

> **For Claude:** REQUIRED SUB-SKILL: Apply these corrections when executing `2026-01-29-saltstack-migration-implementation.md`. Each erratum references the original Task number and Step. Apply corrections inline during execution — do NOT execute the original plan blindly.

**Purpose:** Corrections to the SaltStack migration implementation plan based on verification against official SaltStack documentation (via Context7), the actual codebase models/services, and factory definitions.

**Verified against:** SaltStack 3006+ official docs (salt-api REST CherryPy, execution modules, event bus, presence, reactor)

---

## Critical Issues (Execution Blockers)

### ERRATA-1: Multiple Python modules sharing `__virtualname__` — Tasks 7.1, 7.2, 7.3

**Problem:** Three separate Python files (`inventory_dmi.py`, `inventory_numa.py`, `inventory_network_v2.py`) all declare `__virtualname__ = 'inventory'`. Salt loads modules by virtual name; when multiple files declare the same virtual name, **only the last-loaded module's functions are available**. The others are silently overridden.

**Fix — Option A (Recommended): Single module file**

Merge all three into a single `salt/modules/inventory.py` containing all functions (`collect_dmi`, `collect_numa`, `collect_network_v2`). This is idiomatic Salt — one file per virtual name.

**Consolidate Tasks 7.1 + 7.2 + 7.3 into a single task:**

- Create: `salt/modules/inventory.py` (contains `collect_dmi`, `collect_numa`, `collect_network_v2`)
- Test: `salt/modules/tests/test_inventory.py` (contains all three test classes)

```python
"""
Salt custom execution module for system inventory collection.
Collects DMI, NUMA topology, and advanced network device information.

Usage via salt-api:
    salt 'minion-id' inventory.collect_dmi
    salt 'minion-id' inventory.collect_numa
    salt 'minion-id' inventory.collect_network_v2
"""

import json
import os
import re
import subprocess


__virtualname__ = 'inventory'


def __virtual__():
    return __virtualname__


# --- DMI Collection ---

def collect_dmi():
    """Collect DMI information from the system using dmidecode."""
    try:
        return {
            'bios': _parse_dmi_section(_run_dmidecode('bios')),
            'system': _parse_dmi_section(_run_dmidecode('system')),
            'baseboard': _parse_dmi_section(_run_dmidecode('baseboard')),
        }
    except FileNotFoundError as e:
        return {'error': str(e)}
    except subprocess.CalledProcessError as e:
        return {'error': f'dmidecode failed: {e.returncode}'}


def _run_dmidecode(dmi_type):
    """Run dmidecode for a specific type."""
    type_map = {'bios': '0', 'system': '1', 'baseboard': '2'}
    result = subprocess.run(
        ['dmidecode', '-t', type_map[dmi_type]],
        capture_output=True, text=True, timeout=10
    )
    return result.stdout


def _parse_dmi_section(output):
    """Parse dmidecode output into a dict of key-value pairs."""
    data = {}
    for line in output.splitlines():
        line = line.strip()
        if ':' in line and not line.endswith(':'):
            key, _, value = line.partition(':')
            key = key.strip().lower().replace(' ', '_')
            value = value.strip()
            if value:
                data[key] = value
    return data


# --- NUMA Topology ---

def collect_numa():
    """Collect NUMA topology from /sys/devices/system/node/."""
    numa_nodes = _list_numa_nodes()
    nodes = {}

    for node_dir in numa_nodes:
        node_num = node_dir.replace('node', '')
        base_path = f'/sys/devices/system/node/{node_dir}'
        cpulist = _read_file(f'{base_path}/cpulist').strip()
        meminfo = _read_file(f'{base_path}/meminfo')
        memory_kb = _parse_memtotal(meminfo)
        nodes[node_num] = {'cpulist': cpulist, 'memory_kb': memory_kb}

    return {'node_count': len(numa_nodes), 'nodes': nodes}


def _list_numa_nodes():
    base = '/sys/devices/system/node'
    if not os.path.isdir(base):
        return []
    return sorted([d for d in os.listdir(base) if d.startswith('node') and d[4:].isdigit()])


def _read_file(path):
    try:
        with open(path, 'r') as f:
            return f.read()
    except (IOError, OSError):
        return ''


def _parse_memtotal(meminfo):
    match = re.search(r'MemTotal:\s+(\d+)\s+kB', meminfo)
    return int(match.group(1)) if match else 0


# --- Network V2 (lshw) ---

def collect_network_v2():
    """Collect advanced network device information using lshw."""
    try:
        raw = _run_lshw()
        entries = json.loads(raw)
        devices = []
        for entry in entries:
            config = entry.get('configuration', {})
            devices.append({
                'name': entry.get('logicalname', ''),
                'product': entry.get('product', ''),
                'vendor': entry.get('vendor', ''),
                'mac': entry.get('serial', ''),
                'driver': config.get('driver', ''),
                'speed': config.get('speed', ''),
                'link': config.get('link', ''),
                'pci_slot': entry.get('handle', ''),
            })
        return {'devices': devices}
    except FileNotFoundError as e:
        return {'error': str(e)}
    except (json.JSONDecodeError, subprocess.CalledProcessError) as e:
        return {'error': f'lshw failed: {e}'}


def _run_lshw():
    result = subprocess.run(
        ['lshw', '-class', 'network', '-json'],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout
```

**Fix — Option B: Use unique virtual names per file**

If you want separate files, each must have a unique `__virtualname__`:
- `inventory_dmi.py` → `__virtualname__ = 'inventory_dmi'`
- `inventory_numa.py` → `__virtualname__ = 'inventory_numa'`
- `inventory_network_v2.py` → `__virtualname__ = 'inventory_network_v2'`

This changes Salt call syntax from `salt '*' inventory.collect_dmi` to `salt '*' inventory_dmi.collect_dmi`. All references in Rails services and Salt master config must update accordingly.

**Recommendation:** Use Option A (single file). It matches Salt conventions and keeps the Rails API calls (`inventory.collect_dmi`) as planned.

---

### ERRATA-2: `state.orchestrate` called via `local_async` client — Task 3.1

**Problem:** The plan calls `state.orchestrate` via `run_async` which uses the `local_async` client:

```ruby
jid = @salt_client.run_async(
  @target_node.hostname,
  "state.orchestrate",
  mods: orchestration_mod,
  pillar: pillar_data
)
```

Per SaltStack docs, `state.orchestrate` is a **runner** module, not an execution module. It must be called via the `runner` client, not `local` or `local_async`. Calling it via `local_async` will fail with `'state.orchestrate' is not available`.

**Fix:** Use `state.apply` (execution module) for single-minion state application, or add `run_runner_async` for orchestration via runner.

**For single-minion benchmarks (simpler, recommended):**

Replace `Benchmark::SaltTriggerRunService#call`:

```ruby
def call
  jid = @salt_client.run_async(
    @target_node.hostname,
    "state.apply",
    mods: state_mod,
    pillar: pillar_data
  )

  @benchmark_run.update!(
    status: :running,
    started_at: Time.current
  )

  Result.new(success: true, jid: jid)
rescue SaltApiClient::TargetUnreachable, SaltApiClient::TimeoutError, SaltApiClient::ApiError => e
  @benchmark_run.update!(
    status: :failed,
    error_message: e.message,
    finished_at: Time.current
  )
  Result.new(success: false, error: e.message)
end

private

def state_mod
  benchmark_type = @benchmark_run.benchmark_recipe.benchmark_type
  "benchmark.#{benchmark_type}"
end
```

**Update the test accordingly** — expect `state.apply` not `state.orchestrate`:

```ruby
it "triggers an async Salt state.apply job" do
  expect(salt_client).to receive(:run_async)
    .with(
      "node-01",
      "state.apply",
      mods: "benchmark.mlc",
      pillar: hash_including(run_id: run.uuid)
    )
    .and_return("20260129120000123456")

  result = service.call
  expect(result.success?).to be true
  expect(result.jid).to eq("20260129120000123456")
end
```

**Also update the EventListenerService** (Task 4.1) — change benchmark detection from `state.orchestrate` to `state.apply`:

```ruby
def benchmark_event?(data)
  fun = data["fun"]
  fun == "state.apply" && data.dig("fun_args")&.any? { |arg|
    arg.is_a?(Hash) && arg["mods"]&.start_with?("benchmark.")
  }
end
```

**Also update the reactor filter** (Task 9.1) in `salt/reactor/job_return.sls`:

```yaml
{% if 'benchmark' in data.get('fun', '') or 'state.apply' in data.get('fun', '') %}
```

---

### ERRATA-3: Missing `presence_events: True` in master config — Task 9.1

**Problem:** The plan configures a reactor for `salt/presence/change` events and relies on them in `Salt::EventListenerService` and `Salt::PresenceCheckService`, but `salt/master.d/api.conf` does not enable presence events. Per SaltStack docs, `presence_events` defaults to `False`.

**Fix:** Add to `salt/master.d/api.conf`:

```yaml
# Enable presence detection events on the event bus
presence_events: True
```

---

### ERRATA-4: `BenchmarkRun` has `log_path`, not `log_content` — Task 3.2

**Problem:** `Salt::BenchmarkResultService` updates `run.log_content`:

```ruby
@benchmark_run.update!(
  ...
  log_content: result["log_content"],
  ...
)
```

But the `BenchmarkRun` model has `log_path` (a file path), not `log_content` (inline text). Writing to a non-existent attribute will silently fail or raise `ActiveModel::UnknownAttributeError`.

**Fix:** Write log content to a file and store the path:

```ruby
def call
  # ... existing code ...

  log_file_path = write_log_content(result["log_content"])

  @benchmark_run.update!(
    status: status,
    metrics: result["metrics"] || {},
    started_at: parse_time(result["start_time"]) || @benchmark_run.started_at,
    finished_at: parse_time(result["end_time"]) || Time.current,
    log_path: log_file_path,
    error_message: result["error_message"]
  )

  fetch_artifacts(result["artifacts"] || [])
end

private

def write_log_content(content)
  return nil unless content.present?
  log_dir = Rails.root.join("storage", "benchmark_logs")
  FileUtils.mkdir_p(log_dir)
  path = log_dir.join("#{@benchmark_run.uuid}.log")
  File.write(path, content)
  path.to_s
end
```

**Update the test** — assert against `log_path` instead of `log_content`:

```ruby
it "updates the benchmark run with results" do
  service.call
  run.reload
  expect(run.status).to eq("success")
  expect(run.metrics["gflops"]).to eq(45.67)
  expect(run.finished_at).to be_present
  expect(run.log_path).to be_present
end
```

---

## Important Issues (Correctness)

### ERRATA-5: InventoryMapper DMI test uses symbol keys on string-keyed hash — Task 2.1

**Problem:** The test asserts `result[:dmi][:bios][:vendor]` but `map_dmi_info` returns `@dmi` directly, which has string keys (`"bios"`, `"vendor"`). Symbol key access returns `nil`.

**Fix — Update the test assertions:**

```ruby
it "maps dmi data" do
  result = mapper.call
  expect(result[:dmi]["bios"]["vendor"]).to eq("AMI")
  expect(result[:dmi]["system"]["manufacturer"]).to eq("QCT")
end

it "maps network_v2 data" do
  result = mapper.call
  expect(result[:network_v2]["devices"].first["name"]).to eq("eth0")
end
```

**Or fix the mapper** to deep-symbolize keys (more consistent but more code):

```ruby
def map_dmi_info
  return {} unless @dmi
  @dmi.deep_symbolize_keys
end

def map_network_v2_info
  return {} unless @network_v2
  @network_v2.deep_symbolize_keys
end
```

If using `deep_symbolize_keys`, keep the original test assertions with symbol keys.

---

### ERRATA-6: `TargetUnreachable` only detected on `test.ping` — Task 1.1

**Problem:** The `SaltApiClient#run` method only raises `TargetUnreachable` when `function == "test.ping"` and result is `false`. For other functions, an unreachable minion returns the minion key **missing from the result hash** entirely (empty hash `{}`), which would return `nil` silently.

**Fix — Check for missing minion key:**

```ruby
def run(target, function, **kwargs)
  ensure_authenticated
  body = { client: "local", tgt: target, fun: function }.merge(kwargs)
  response = post("/", body)
  data = parse_response(response)
  result = data.dig("return", 0)

  unless result.is_a?(Hash) && result.key?(target)
    raise TargetUnreachable, "Minion '#{target}' did not return a result"
  end

  minion_result = result[target]

  if minion_result == false && function == "test.ping"
    raise TargetUnreachable, "Minion '#{target}' is not responding"
  end

  minion_result
end
```

**Update the test** for the unreachable case:

```ruby
it "raises TargetUnreachable when minion is not in the result" do
  stub_request(:post, "#{base_url}/")
    .to_return(
      status: 200,
      body: { return: [{}] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

  expect { client.run("node-01", "grains.items") }
    .to raise_error(SaltApiClient::TargetUnreachable)
end
```

---

### ERRATA-7: Missing `file_recv: True` for `cp.push` — Task 9.1

**Problem:** The plan uses `cp.push` and `cp.push_dir` in benchmark result collection and SLS states, but the master config does not enable `file_recv`. Per Salt docs, `file_recv` defaults to `False` and must be enabled for minions to push files to the master.

**Fix:** Add to `salt/master.d/api.conf`:

```yaml
# Allow minions to push files to the master via cp.push
file_recv: True
```

---

### ERRATA-8: `BenchmarkRecipe` factory lacks `:mlc` trait — Task 3.1

**Problem:** The plan test uses `create(:benchmark_recipe, benchmark_type: :mlc)` but the factory only has `:hpcg` and `:hpl` traits.

**Fix — Check if `benchmark_type` is a column.** If it is, the factory call should work as-is (FactoryBot passes unknown attributes to the model). If `benchmark_type` is mapped from the recipe `slug` or `name`, adjust:

```ruby
# If benchmark_type is a real column, add trait to factory:
trait :mlc do
  name { "Intel Memory Latency Checker" }
  slug { "mlc" }
  benchmark_type { :mlc }
  command { "mlc" }
end
```

Verify by checking the `benchmark_recipes` table schema (`bin/rails db:schema:dump` or `db/schema.rb`).

---

### ERRATA-9: SSE `/events` endpoint token format — Task 4.2

**Problem:** The plan's `events` method uses `X-Auth-Token` header for the GET request to `/events`. Per SaltStack docs, the SSE endpoint conventionally uses a **query parameter**:

```bash
curl -SsNk https://salt-api.example.com:8000/events?token=TOKEN
```

And from the JavaScript docs:
```javascript
new EventSource('/events?salt_token=' + XAuthToken);
```

**Assessment:** The `X-Auth-Token` header *does work* for the CherryPy REST API (it checks both header and query param). The plan's approach is valid but less conventional. No code change required, but add a comment:

```ruby
def events(&block)
  ensure_authenticated
  # salt-api accepts token via X-Auth-Token header or ?token= query param
  # Using header approach for consistency with other methods
  uri = URI.parse("#{@base_url}/events")
  # ...
end
```

---

### ERRATA-10: Login endpoint Content-Type — Task 1.1

**Problem:** The plan sends JSON (`Content-Type: application/json`) to `/login`. Salt API docs show form-encoded examples. CherryPy *does* accept both formats (it parses based on Content-Type), but form-encoded is the conventional and more widely tested path.

**Assessment:** JSON works. No change required, but consider adding a note about this in the implementation. If issues arise during integration testing, switch to form-encoded for `/login` only:

```ruby
def authenticate
  uri = URI.parse("#{@base_url}/login")
  request = Net::HTTP::Post.new(uri)
  request.set_form_data(
    "username" => @username,
    "password" => @password,
    "eauth" => "pam"
  )
  response = execute_request(uri, request)
  # ...
end
```

---

### ERRATA-11: Reactor Jinja template safety — Task 9.1

**Problem:** In `salt/reactor/job_return.sls`, the line:

```yaml
"return": {{ data.get('return', '{}') | json }}
```

The `| json` Jinja filter may not correctly serialize nested Python dicts that come from Salt's event data. If `data['return']` is a complex nested structure, this can produce malformed JSON.

**Fix — Use `| tojson` filter (the standard Jinja2 filter for JSON serialization):**

```yaml
"return": {{ data.get('return', {}) | tojson }}
```

Also fix the overall data serialization to use `tojson` consistently:

```yaml
{% if 'benchmark' in data.get('fun', '') or 'state.apply' in data.get('fun', '') %}
notify_rails:
  runner.http.query:
    - url: {{ salt['config.get']('rails_webhook_url', 'http://localhost:3000/api/v1/salt/events') }}
    - method: POST
    - header_dict:
        Content-Type: application/json
        Authorization: "Bearer {{ salt['config.get']('rails_api_token', '') }}"
    - data: {{ {"tag": tag, "fun": data['fun'], "id": data['id'], "jid": data['jid'], "retcode": data.get('retcode', -1), "return": data.get('return', {})} | tojson }}
{% endif %}
```

---

### ERRATA-12: `external_auth` config — `state.orchestrate` → `state.apply` — Task 9.1

**Problem:** Following ERRATA-2, the external auth config grants `state.orchestrate` under `@runner`. Since we're now using `state.apply` (execution module, not runner), update permissions:

**Fix:**

```yaml
external_auth:
  pam:
    rails_salt_user:
      - '*':
        - grains.items
        - inventory.collect_dmi
        - inventory.collect_numa
        - inventory.collect_network_v2
        - benchmark.run_hpcg
        - benchmark.run_mlc
        - benchmark.cancel
        - test.ping
        - state.apply
        - cp.push
        - cp.push_dir
      - '@runner':
        - manage.status
```

---

## Minor Issues

### ERRATA-13: `Inventory::SaltCollectService` test references — Task 2.2

**Problem:** The test stubs `salt_client.run("node-01", "grains.items")` but the real Salt function is `grains.items` (returns all grains). This is correct. However, the ProcessStateService mock:

```ruby
expect(Inventory::ProcessStateService).to receive(:new).with(
  hash_including(node_id: node.id, raw_json: hash_including(:host, :cpu, :memory))
).and_call_original
```

This calls `.and_call_original` which will try to actually process and persist data. The test should either:
- Not use `.and_call_original` (mock the return)
- Or set up proper DB fixtures

**Fix:**

```ruby
it "delegates to ProcessStateService with mapped data" do
  mock_result = Inventory::ProcessStateService::Result.new(
    success: true, state_created: true, node_state: nil, error: nil, error_code: nil
  )
  expect(Inventory::ProcessStateService).to receive(:new).with(
    hash_including(node_id: node.id, raw_json: hash_including(:host, :cpu, :memory))
  ).and_return(instance_double(Inventory::ProcessStateService, call: mock_result))

  service.call
end
```

**Note:** Verify `ProcessStateService::Result` struct fields match: `success`, `state_created`, `node_state`, `error`, `error_code`.

---

### ERRATA-14: `SaltCollectService` Result struct field mismatch — Task 2.2

**Problem:** The plan defines:

```ruby
Result = Struct.new(:success, :error, :state_created, :node_state, keyword_init: true)
```

But `ProcessStateService` returns a result with fields: `success`, `state_created`, `node_state`, `error`, `error_code`. The `SaltCollectService` proxies these. Ensure field alignment:

```ruby
Result = Struct.new(:success, :error, :state_created, :node_state, :error_code, keyword_init: true) do
  def success?
    success
  end
end
```

---

### ERRATA-15: SLS state `module.run` syntax for Salt 3006+ — Task 8.1, 8.2

**Problem:** The `module.run` syntax in SLS states changed in Salt 3006. The new format uses the function name as a keyword arg:

**Old format (pre-3006):**
```yaml
run_hpcg:
  module.run:
    - name: benchmark.run_hpcg
    - work_dir: /tmp/hpcg
```

**New format (3006+):**
```yaml
run_hpcg:
  module.run:
    - benchmark.run_hpcg:
      - work_dir: {{ pillar.get('work_dir', '/tmp/hpcg') }}
      - run_id: {{ pillar.get('run_id', '') }}
```

**Or enable the old syntax** by setting `use_superseded: - module.run` in the master/minion config. Since the plan targets Salt 3006+, use the new syntax or add the compatibility flag.

**Fix — Use new syntax in all SLS files:**

`salt/states/benchmark/hpcg/execute.sls`:
```yaml
run_hpcg:
  module.run:
    - benchmark.run_hpcg:
      - work_dir: {{ pillar.get('work_dir', '/tmp/hpcg') }}
      - run_id: {{ pillar.get('run_id', '') }}
    - require:
      - cmd: hpcg_binary_check
```

`salt/states/benchmark/mlc/execute.sls`:
```yaml
run_mlc:
  module.run:
    - benchmark.run_mlc:
      - work_dir: {{ pillar.get('work_dir', '/tmp/mlc') }}
      - run_id: {{ pillar.get('run_id', '') }}
      - binary_path: {{ pillar.get('binary_path', 'mlc') }}
      - profile: {{ pillar.get('profile', 'quick') }}
    - require:
      - cmd: mlc_binary_check
```

---

### ERRATA-16: `cp.push_dir` glob syntax — Task 8.1, 8.2

**Problem:** The SLS `cp.push_dir` call uses `glob: "*.txt,*.dat,*.log"`. The `cp.push_dir` `glob` parameter expects a single glob pattern, not comma-separated. Multiple patterns need multiple calls or a broader glob.

**Fix:** Use separate `module.run` calls or a broad glob:

```yaml
push_artifacts:
  module.run:
    - cp.push_dir:
      - path: {{ pillar.get('work_dir', '/tmp/hpcg') }}
      - glob: "*"
    - require:
      - module: run_hpcg
```

Or call `cp.push` for each file extension separately.

---

## Summary Checklist

When executing the original plan, apply these corrections:

| Erratum | Task(s) | Severity | Action |
|---------|---------|----------|--------|
| ERRATA-1 | 7.1-7.3 | CRITICAL | Merge into single `inventory.py` |
| ERRATA-2 | 3.1, 4.1, 9.1 | CRITICAL | Use `state.apply` not `state.orchestrate` |
| ERRATA-3 | 9.1 | CRITICAL | Add `presence_events: True` |
| ERRATA-4 | 3.2 | CRITICAL | Use `log_path` not `log_content` |
| ERRATA-5 | 2.1 | IMPORTANT | Fix string vs symbol key access in tests |
| ERRATA-6 | 1.1 | IMPORTANT | Detect missing minion in result hash |
| ERRATA-7 | 9.1 | IMPORTANT | Add `file_recv: True` |
| ERRATA-8 | 3.1 | IMPORTANT | Add `:mlc` factory trait or verify schema |
| ERRATA-9 | 4.2 | MINOR | Add comment about token format |
| ERRATA-10 | 1.1 | MINOR | Note about form-encoded alternative |
| ERRATA-11 | 9.1 | IMPORTANT | Use `tojson` not `json` Jinja filter |
| ERRATA-12 | 9.1 | IMPORTANT | Update eauth: `state.apply` not `state.orchestrate` |
| ERRATA-13 | 2.2 | MINOR | Don't use `.and_call_original` |
| ERRATA-14 | 2.2 | MINOR | Add `error_code` to Result struct |
| ERRATA-15 | 8.1-8.2 | IMPORTANT | Use Salt 3006+ `module.run` syntax |
| ERRATA-16 | 8.1-8.2 | MINOR | Fix `cp.push_dir` glob parameter |
