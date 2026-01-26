// Package bmc provides a unified client factory for BMC communication.
// It supports auto-detection between Redfish and IPMI protocols.
package bmc

import (
	"context"
	"fmt"

	"github.com/yuka1981/diagnostic-tools/agent/bmc/ipmi"
	"github.com/yuka1981/diagnostic-tools/agent/bmc/redfish"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// Protocol constants define the supported BMC communication protocols.
const (
	ProtocolAuto    = "auto"
	ProtocolRedfish = "redfish"
	ProtocolIPMI    = "ipmi"
	protocolUnknown = "unknown"
)

// ClientFactory creates BMC clients. This interface allows for dependency injection
// and easier testing.
type ClientFactory interface {
	// NewRedfishClient creates a new Redfish client.
	NewRedfishClient(config ports.BMCConfig) ports.BMCClient
	// NewIPMIClient creates a new IPMI client.
	NewIPMIClient(config ports.BMCConfig) ports.BMCClient
}

// DefaultClientFactory is the production implementation of ClientFactory.
type DefaultClientFactory struct{}

// NewRedfishClient creates a new Redfish client.
//
//nolint:gocritic // config passed by value to match existing API
func (f *DefaultClientFactory) NewRedfishClient(config ports.BMCConfig) ports.BMCClient {
	return redfish.NewClient(config)
}

// NewIPMIClient creates a new IPMI client.
//
//nolint:gocritic // config passed by value to match existing API
func (f *DefaultClientFactory) NewIPMIClient(config ports.BMCConfig) ports.BMCClient {
	return ipmi.NewClient(config)
}

// defaultFactory is the global default factory instance.
var defaultFactory ClientFactory = &DefaultClientFactory{}

// NewClient creates a BMC client based on configuration.
// If protocol is "auto" or empty, it tries Redfish first, then falls back to IPMI.
// If protocol is "redfish" or "ipmi", it uses that protocol directly.
//
//nolint:gocritic // config passed by value to match existing API
func NewClient(ctx context.Context, config ports.BMCConfig) (ports.BMCClient, error) {
	return NewClientWithFactory(ctx, config, defaultFactory)
}

// NewClientWithFactory creates a BMC client using the specified factory.
// This is primarily used for testing with mock factories.
//
//nolint:gocritic // config passed by value to match existing API
func NewClientWithFactory(
	ctx context.Context,
	config ports.BMCConfig,
	factory ClientFactory,
) (ports.BMCClient, error) {
	switch config.Protocol {
	case ProtocolRedfish:
		return newRedfishClient(ctx, config, factory)
	case ProtocolIPMI:
		return newIPMIClient(ctx, config, factory)
	case ProtocolAuto, "":
		// Try Redfish first
		client, err := newRedfishClient(ctx, config, factory)
		if err == nil {
			return client, nil
		}
		// Fall back to IPMI
		return newIPMIClient(ctx, config, factory)
	default:
		return nil, fmt.Errorf("unsupported protocol: %s", config.Protocol)
	}
}

// newRedfishClient creates and connects a Redfish client.
//
//nolint:gocritic // config passed by value to match existing API
func newRedfishClient(
	ctx context.Context,
	config ports.BMCConfig,
	factory ClientFactory,
) (ports.BMCClient, error) {
	client := factory.NewRedfishClient(config)
	if err := client.Connect(ctx); err != nil {
		return nil, err
	}
	return client, nil
}

// newIPMIClient creates and connects an IPMI client.
//
//nolint:gocritic // config passed by value to match existing API
func newIPMIClient(
	ctx context.Context,
	config ports.BMCConfig,
	factory ClientFactory,
) (ports.BMCClient, error) {
	client := factory.NewIPMIClient(config)
	if err := client.Connect(ctx); err != nil {
		return nil, err
	}
	return client, nil
}

// DetectedProtocol returns which protocol was used for connection.
// It uses type assertion to identify the underlying client type.
func DetectedProtocol(client ports.BMCClient) string {
	switch client.(type) {
	case *redfish.Client:
		return ProtocolRedfish
	case *ipmi.Client:
		return ProtocolIPMI
	default:
		return protocolUnknown
	}
}
