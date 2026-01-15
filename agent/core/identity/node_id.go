package identity

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
)

const (
	// DefaultIDPath is where the node identifier is stored
	DefaultIDPath = "node_id"
)

// forcedNodeID stores an externally-injected node ID (e.g., from CLI flag)
// When set, this takes priority over file-based or generated IDs
var forcedNodeID string

// SetForcedNodeID sets an externally-provided node ID that takes priority
// over any file-based or generated ID. This is used when the server
// injects a known UUID via CLI flag to ensure identity consistency.
func SetForcedNodeID(id string) {
	forcedNodeID = id
}

// GetForcedNodeID returns the currently forced node ID, if any
func GetForcedNodeID() string {
	return forcedNodeID
}

// GetOrGenerateNodeID implements the Hybrid UUID Strategy
// Priority: 1) Forced ID (from CLI), 2) File-based ID, 3) Generated ID
func GetOrGenerateNodeID(configDir string) (string, error) {
	// Priority 1: Check for forced/injected node ID (from CLI flag)
	if forcedNodeID != "" {
		return forcedNodeID, nil
	}

	idPath := filepath.Join(configDir, DefaultIDPath)

	// Priority 2: Try reading existing ID from file
	if data, err := os.ReadFile(idPath); err == nil {
		id := strings.TrimSpace(string(data))
		if id != "" {
			return id, nil
		}
	}

	// Priority 3: Generate from hardware fingerprint
	id := GenerateFingerprint()

	// Persist generated ID for future use
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return id, fmt.Errorf("failed to create config directory: %w", err)
	}

	if err := os.WriteFile(idPath, []byte(id), 0600); err != nil {
		// Log warning but return ID anyway so agent can function
		fmt.Fprintf(os.Stderr, "Warning: failed to persist node_id to %s: %v\n", idPath, err)
	}

	return id, nil
}

// GenerateFingerprint creates a unique hash based on hardware traits
func GenerateFingerprint() string {
	var sb strings.Builder

	// Try Linux Machine ID
	if data, err := os.ReadFile("/etc/machine-id"); err == nil {
		sb.Write(data)
	} else if data, err := os.ReadFile("/var/lib/dbus/machine-id"); err == nil {
		sb.Write(data)
	}

	// Fallback/Supplement: MAC Address of first active interface
	if interfaces, err := net.Interfaces(); err == nil {
		for _, iface := range interfaces {
			if iface.Flags&net.FlagLoopback == 0 && len(iface.HardwareAddr) > 0 {
				sb.WriteString(iface.HardwareAddr.String())
				break
			}
		}
	}

	// If everything failed (unlikely on Linux), use hostname as last resort
	if sb.Len() == 0 {
		if hostname, err := os.Hostname(); err == nil {
			sb.WriteString(hostname)
		}
	}

	hash := sha256.Sum256([]byte(sb.String()))
	return hex.EncodeToString(hash[:])
}
