// Package metrics provides Prometheus metrics publishing for BMC sensor data.
package metrics

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// PushgatewayClient pushes metrics to Prometheus Pushgateway.
type PushgatewayClient struct {
	url        string
	httpClient *http.Client
	job        string
}

// NewPushgatewayClient creates a new Pushgateway client.
func NewPushgatewayClient(url string) *PushgatewayClient {
	return &PushgatewayClient{
		url:        strings.TrimSuffix(url, "/"),
		httpClient: &http.Client{Timeout: 30 * time.Second},
		job:        "qis_bmc_collector",
	}
}

// NewPushgatewayClientWithHTTPClient creates a new Pushgateway client with a custom HTTP client.
// This is useful for testing or custom transport configurations.
func NewPushgatewayClientWithHTTPClient(url string, httpClient *http.Client) *PushgatewayClient {
	return &PushgatewayClient{
		url:        strings.TrimSuffix(url, "/"),
		httpClient: httpClient,
		job:        "qis_bmc_collector",
	}
}

// SetJob sets the job label for metrics.
func (c *PushgatewayClient) SetJob(job string) {
	c.job = job
}

// PushSensors pushes sensor readings to Pushgateway.
func (c *PushgatewayClient) PushSensors(ctx context.Context, nodeName string, sensors []model.BMCSensorReading) error {
	body := formatSensorMetrics(nodeName, sensors)
	return c.push(ctx, nodeName, body)
}

// formatSensorMetrics formats sensors in Prometheus exposition format.
func formatSensorMetrics(nodeName string, sensors []model.BMCSensorReading) string {
	var buf bytes.Buffer

	for _, s := range sensors {
		// Determine metric name based on unit
		metricName := sensorMetricName(s.Unit)

		// Write metric line: metric_name{labels} value
		fmt.Fprintf(&buf, "%s{node=\"%s\",sensor=\"%s\"} %g\n",
			metricName, sanitizeLabel(nodeName), sanitizeLabel(s.Name), s.Value)

		// Write status metric
		statusValue := statusToValue(s.Status)
		fmt.Fprintf(&buf, "qis_bmc_sensor_status{node=\"%s\",sensor=\"%s\"} %d\n",
			sanitizeLabel(nodeName), sanitizeLabel(s.Name), statusValue)
	}

	return buf.String()
}

// sensorMetricName returns Prometheus metric name based on unit.
func sensorMetricName(unit string) string {
	switch strings.ToLower(unit) {
	case "degrees c", "celsius", "c":
		return "qis_bmc_temperature_celsius"
	case "rpm":
		return "qis_bmc_fan_rpm"
	case "watts", "w":
		return "qis_bmc_power_watts"
	case "volts", "v":
		return "qis_bmc_voltage_volts"
	case "amps", "a":
		return "qis_bmc_current_amps"
	default:
		return "qis_bmc_sensor_value"
	}
}

// statusToValue converts status string to numeric value.
func statusToValue(status string) int {
	switch strings.ToLower(status) {
	case "ok", "nominal":
		return 0
	case "warning":
		return 1
	case "critical":
		return 2
	default:
		return -1 // unknown
	}
}

// sanitizeLabel sanitizes label value for Prometheus.
func sanitizeLabel(s string) string {
	// Replace problematic characters
	s = strings.ReplaceAll(s, "\"", "")
	s = strings.ReplaceAll(s, "\\", "")
	s = strings.ReplaceAll(s, "\n", " ")
	return s
}

// push sends metrics to Pushgateway.
func (c *PushgatewayClient) push(ctx context.Context, nodeName, body string) error {
	// Pushgateway URL format: /metrics/job/<job>/instance/<instance>
	url := fmt.Sprintf("%s/metrics/job/%s/instance/%s", c.url, c.job, nodeName)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "text/plain")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to push metrics: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("pushgateway returned %d: %s", resp.StatusCode, string(respBody))
	}

	return nil
}
