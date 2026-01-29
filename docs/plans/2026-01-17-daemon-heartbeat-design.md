# Daemon Mode & Heartbeat Design

**Date:** 2026-01-17
**Status:** Approved

## Overview

Replace WebSocket-based daemon mode with HTTP-only heartbeat polling. The agent runs as a daemon, periodically sending heartbeat requests to the Rails server.

## Architecture

```
start command (cmd/start.go)
    │
    ├── Signal handler (SIGTERM/SIGINT)
    │
    └── Heartbeat loop (ticker)
            │
            └── HeartbeatService (core/heartbeat/service.go)
                    │
                    └── HTTP POST to /api/v1/nodes/{uuid}/heartbeat
```

## Data Flow

1. `start` command validates required flags (`--node-uuid`, `--token`)
2. Creates HeartbeatService with server URL, token, node UUID, version
3. Sends initial heartbeat immediately
4. Starts goroutine with `time.Ticker` at configured interval
5. Each tick calls `heartbeatService.Send(ctx)`
6. Main goroutine blocks on signal channel
7. On SIGTERM/SIGINT, cancels context and exits gracefully

## HeartbeatService

**File:** `agent/core/heartbeat/service.go`

**Structure:**
```go
type Service struct {
    baseURL  string
    token    string
    nodeID   string
    version  string
    hostname string
    client   *http.Client
}

func New(baseURL, token, nodeID, version string) *Service
func (s *Service) Send(ctx context.Context) error
```

**Send() behavior:**
1. Build endpoint: `{baseURL}/api/v1/nodes/{nodeID}/heartbeat`
2. Create JSON payload: `{uuid, timestamp, version}`
3. POST with headers:
   - `Authorization: Bearer {token}`
   - `Content-Type: application/json`
   - `X-Node-ID: {nodeID}`
   - `X-Hostname: {hostname}`
   - `X-Agent-Version: {version}`
4. Log result, return error on non-2xx (non-fatal)

**Heartbeat Payload:**
```json
{
  "uuid": "abc123...",
  "timestamp": "2026-01-17T10:30:00Z",
  "version": "1.2.3"
}
```

## Modified start Command

**File:** `agent/cmd/start.go`

**Required flags:**
- `--node-uuid` (required) — Rails-known UUID, passed during agent install
- `--token` (required, env: `AGENT_TOKEN`) — authentication token

**Optional flags:**
- `--server` (default: `http://localhost:3000`) — Rails server URL
- `--heartbeat-interval` (default: `60s`) — interval between heartbeats

**Removed:**
- `agentHandler` struct and methods
- WebSocket `stream.Client`
- Imports: `stream`, `inventory`, `collector`, `infrastructure`

## Node Identification

**Strategy:** Server-injected UUID only.

The `--node-uuid` flag is required. Rails must provide the UUID when starting the agent (e.g., via systemd unit file generated during remote install).

Headers sent with each request:
- `X-Node-ID` — UUID from `--node-uuid`
- `X-Hostname` — hostname for human-readable context
- `X-Agent-Version` — for compatibility tracking

## Error Handling

Heartbeat is "best effort" — failures don't crash the daemon:
- Network errors: log warning, continue
- 401 Unauthorized: log error, continue
- 5xx errors: log warning, continue

The server detects missing heartbeats to mark nodes offline.

## Files Changed

| File | Action |
|------|--------|
| `agent/core/heartbeat/service.go` | New |
| `agent/cmd/start.go` | Modified (simplified) |

## Testing

- Unit test `heartbeat.Service.Send()` with `httptest` server
- Manual: `qis-agent start --node-uuid X --token Y --heartbeat-interval 5s`
