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

// GetOrGenerateNodeID implements the Hybrid UUID Strategy
func GetOrGenerateNodeID(configDir string) (string, error) {
	idPath := filepath.Join(configDir, DefaultIDPath)

	// 1. Try reading existing ID from file
	if data, err := os.ReadFile(idPath); err == nil {
		id := strings.TrimSpace(string(data))
		if id != "" {
			return id, nil
		}
	}

	// 2. Generate from hardware fingerprint
	id := GenerateFingerprint()

	// 3. Persist generated ID
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
