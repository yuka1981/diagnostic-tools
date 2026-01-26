package metrics

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

func TestNewPushgatewayClient(t *testing.T) {
	tests := []struct {
		name        string
		url         string
		expectedURL string
	}{
		{
			name:        "URL without trailing slash",
			url:         "http://localhost:9091",
			expectedURL: "http://localhost:9091",
		},
		{
			name:        "URL with trailing slash",
			url:         "http://localhost:9091/",
			expectedURL: "http://localhost:9091",
		},
		{
			name:        "URL with multiple trailing slashes",
			url:         "http://localhost:9091///",
			expectedURL: "http://localhost:9091//", // TrimSuffix only removes one
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client := NewPushgatewayClient(tt.url)

			if client.url != tt.expectedURL {
				t.Errorf("expected URL %q, got %q", tt.expectedURL, client.url)
			}
			if client.job != "qis_bmc_collector" {
				t.Errorf("expected job %q, got %q", "qis_bmc_collector", client.job)
			}
			if client.httpClient == nil {
				t.Error("expected httpClient to be set")
			}
		})
	}
}

func TestPushgatewayClient_SetJob(t *testing.T) {
	client := NewPushgatewayClient("http://localhost:9091")
	client.SetJob("custom_job")

	if client.job != "custom_job" {
		t.Errorf("expected job %q, got %q", "custom_job", client.job)
	}
}

func TestPushgatewayClient_PushSensors_Success(t *testing.T) {
	var receivedBody string
	var receivedURL string
	var receivedContentType string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedURL = r.URL.Path
		receivedContentType = r.Header.Get("Content-Type")

		body := make([]byte, r.ContentLength)
		_, _ = r.Body.Read(body)
		receivedBody = string(body)

		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewPushgatewayClientWithHTTPClient(server.URL, server.Client())

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
		{Name: "Fan1", Value: 3500, Unit: "RPM", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expectedURL := "/metrics/job/qis_bmc_collector/instance/node001"
	if receivedURL != expectedURL {
		t.Errorf("expected URL %q, got %q", expectedURL, receivedURL)
	}

	if receivedContentType != "text/plain" {
		t.Errorf("expected Content-Type %q, got %q", "text/plain", receivedContentType)
	}

	// Check that metrics are in the body
	if !strings.Contains(receivedBody, "qis_bmc_temperature_celsius") {
		t.Error("expected temperature metric in body")
	}
	if !strings.Contains(receivedBody, "qis_bmc_fan_rpm") {
		t.Error("expected fan RPM metric in body")
	}
}

func TestPushgatewayClient_PushSensors_AcceptedStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusAccepted)
	}))
	defer server.Close()

	client := NewPushgatewayClientWithHTTPClient(server.URL, server.Client())

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)

	if err != nil {
		t.Fatalf("unexpected error for Accepted status: %v", err)
	}
}

func TestPushgatewayClient_PushSensors_ServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("Internal server error"))
	}))
	defer server.Close()

	client := NewPushgatewayClientWithHTTPClient(server.URL, server.Client())

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)

	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "500") {
		t.Errorf("expected error to contain status code 500, got %q", err.Error())
	}
	if !strings.Contains(err.Error(), "Internal server error") {
		t.Errorf("expected error to contain response body, got %q", err.Error())
	}
}

func TestPushgatewayClient_PushSensors_BadRequest(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte("Bad request"))
	}))
	defer server.Close()

	client := NewPushgatewayClientWithHTTPClient(server.URL, server.Client())

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)

	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "400") {
		t.Errorf("expected error to contain status code 400, got %q", err.Error())
	}
}

func TestPushgatewayClient_PushSensors_ConnectionError(t *testing.T) {
	// Use a URL that will fail to connect
	client := NewPushgatewayClient("http://localhost:1") // Port 1 should fail

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)

	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "failed to push metrics") {
		t.Errorf("expected error to contain 'failed to push metrics', got %q", err.Error())
	}
}

func TestPushgatewayClient_PushSensors_Timeout(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(200 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	// Create client with very short timeout
	httpClient := &http.Client{Timeout: 50 * time.Millisecond}
	client := NewPushgatewayClientWithHTTPClient(server.URL, httpClient)

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)

	if err == nil {
		t.Fatal("expected timeout error, got nil")
	}
	if !strings.Contains(err.Error(), "failed to push metrics") {
		t.Errorf("expected error to contain 'failed to push metrics', got %q", err.Error())
	}
}

func TestPushgatewayClient_PushSensors_ContextCanceled(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(500 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewPushgatewayClientWithHTTPClient(server.URL, server.Client())

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(ctx, "node001", sensors)

	if err == nil {
		t.Fatal("expected context canceled error, got nil")
	}
}

func TestFormatSensorMetrics(t *testing.T) {
	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
		{Name: "Fan1", Value: 3500, Unit: "RPM", Status: "Warning"},
		{Name: "PSU Power", Value: 450.2, Unit: "Watts", Status: "Critical"},
		{Name: "12V Rail", Value: 12.1, Unit: "Volts", Status: "nominal"},
		{Name: "PSU Current", Value: 37.5, Unit: "Amps", Status: "unknown"},
	}

	result := formatSensorMetrics("node001", sensors)

	// Check temperature metric
	if !strings.Contains(result, `qis_bmc_temperature_celsius{node="node001",sensor="CPU0 Temp"} 45.5`) {
		t.Error("expected temperature metric with correct labels and value")
	}

	// Check fan RPM metric
	if !strings.Contains(result, `qis_bmc_fan_rpm{node="node001",sensor="Fan1"} 3500`) {
		t.Error("expected fan RPM metric with correct labels and value")
	}

	// Check power metric
	if !strings.Contains(result, `qis_bmc_power_watts{node="node001",sensor="PSU Power"} 450.2`) {
		t.Error("expected power metric with correct labels and value")
	}

	// Check voltage metric
	if !strings.Contains(result, `qis_bmc_voltage_volts{node="node001",sensor="12V Rail"} 12.1`) {
		t.Error("expected voltage metric with correct labels and value")
	}

	// Check current metric
	if !strings.Contains(result, `qis_bmc_current_amps{node="node001",sensor="PSU Current"} 37.5`) {
		t.Error("expected current metric with correct labels and value")
	}

	// Check status metrics
	if !strings.Contains(result, `qis_bmc_sensor_status{node="node001",sensor="CPU0 Temp"} 0`) {
		t.Error("expected OK status to be 0")
	}
	if !strings.Contains(result, `qis_bmc_sensor_status{node="node001",sensor="Fan1"} 1`) {
		t.Error("expected Warning status to be 1")
	}
	if !strings.Contains(result, `qis_bmc_sensor_status{node="node001",sensor="PSU Power"} 2`) {
		t.Error("expected Critical status to be 2")
	}
	if !strings.Contains(result, `qis_bmc_sensor_status{node="node001",sensor="12V Rail"} 0`) {
		t.Error("expected nominal status to be 0")
	}
	if !strings.Contains(result, `qis_bmc_sensor_status{node="node001",sensor="PSU Current"} -1`) {
		t.Error("expected unknown status to be -1")
	}
}

func TestFormatSensorMetrics_EmptySensors(t *testing.T) {
	result := formatSensorMetrics("node001", []model.BMCSensorReading{})

	if result != "" {
		t.Errorf("expected empty string for empty sensors, got %q", result)
	}
}

func TestSensorMetricName(t *testing.T) {
	tests := []struct {
		unit     string
		expected string
	}{
		// Temperature variations
		{"degrees c", "qis_bmc_temperature_celsius"},
		{"Degrees C", "qis_bmc_temperature_celsius"},
		{"DEGREES C", "qis_bmc_temperature_celsius"},
		{"celsius", "qis_bmc_temperature_celsius"},
		{"Celsius", "qis_bmc_temperature_celsius"},
		{"c", "qis_bmc_temperature_celsius"},
		{"C", "qis_bmc_temperature_celsius"},

		// Fan RPM
		{"rpm", "qis_bmc_fan_rpm"},
		{"RPM", "qis_bmc_fan_rpm"},
		{"Rpm", "qis_bmc_fan_rpm"},

		// Power
		{"watts", "qis_bmc_power_watts"},
		{"Watts", "qis_bmc_power_watts"},
		{"WATTS", "qis_bmc_power_watts"},
		{"w", "qis_bmc_power_watts"},
		{"W", "qis_bmc_power_watts"},

		// Voltage
		{"volts", "qis_bmc_voltage_volts"},
		{"Volts", "qis_bmc_voltage_volts"},
		{"VOLTS", "qis_bmc_voltage_volts"},
		{"v", "qis_bmc_voltage_volts"},
		{"V", "qis_bmc_voltage_volts"},

		// Current
		{"amps", "qis_bmc_current_amps"},
		{"Amps", "qis_bmc_current_amps"},
		{"AMPS", "qis_bmc_current_amps"},
		{"a", "qis_bmc_current_amps"},
		{"A", "qis_bmc_current_amps"},

		// Unknown units
		{"", "qis_bmc_sensor_value"},
		{"percentage", "qis_bmc_sensor_value"},
		{"unknown", "qis_bmc_sensor_value"},
		{"CFM", "qis_bmc_sensor_value"},
	}

	for _, tt := range tests {
		t.Run(tt.unit, func(t *testing.T) {
			result := sensorMetricName(tt.unit)
			if result != tt.expected {
				t.Errorf("sensorMetricName(%q) = %q, expected %q", tt.unit, result, tt.expected)
			}
		})
	}
}

func TestStatusToValue(t *testing.T) {
	tests := []struct {
		status   string
		expected int
	}{
		// OK status
		{"ok", 0},
		{"OK", 0},
		{"Ok", 0},
		{"nominal", 0},
		{"Nominal", 0},
		{"NOMINAL", 0},

		// Warning status
		{"warning", 1},
		{"Warning", 1},
		{"WARNING", 1},

		// Critical status
		{"critical", 2},
		{"Critical", 2},
		{"CRITICAL", 2},

		// Unknown status
		{"", -1},
		{"unknown", -1},
		{"error", -1},
		{"degraded", -1},
		{"n/a", -1},
	}

	for _, tt := range tests {
		t.Run(tt.status, func(t *testing.T) {
			result := statusToValue(tt.status)
			if result != tt.expected {
				t.Errorf("statusToValue(%q) = %d, expected %d", tt.status, result, tt.expected)
			}
		})
	}
}

func TestSanitizeLabel(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "no special characters",
			input:    "CPU0 Temp",
			expected: "CPU0 Temp",
		},
		{
			name:     "contains quotes",
			input:    `Sensor "Main"`,
			expected: "Sensor Main",
		},
		{
			name:     "contains backslashes",
			input:    `Sensor\Path`,
			expected: "SensorPath",
		},
		{
			name:     "contains newlines",
			input:    "Sensor\nName",
			expected: "Sensor Name",
		},
		{
			name:     "multiple special characters",
			input:    "Sensor \"Name\"\nWith\\Special",
			expected: "Sensor Name WithSpecial", // backslash removed before newline replaced
		},
		{
			name:     "empty string",
			input:    "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := sanitizeLabel(tt.input)
			if result != tt.expected {
				t.Errorf("sanitizeLabel(%q) = %q, expected %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestFormatSensorMetrics_SpecialCharactersInLabels(t *testing.T) {
	sensors := []model.BMCSensorReading{
		{Name: "CPU \"Main\"", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	result := formatSensorMetrics("node001", sensors)

	// Should not contain raw quotes in labels
	if strings.Contains(result, `sensor="CPU "Main""`) {
		t.Error("expected quotes to be sanitized in sensor name")
	}

	// Should contain sanitized version
	if !strings.Contains(result, `sensor="CPU Main"`) {
		t.Error("expected sanitized sensor name")
	}
}

func TestFormatSensorMetrics_SpecialCharactersInNodeName(t *testing.T) {
	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	result := formatSensorMetrics("node\"001", sensors)

	// Should not contain raw quotes in node name
	if strings.Contains(result, `node="node"001"`) {
		t.Error("expected quotes to be sanitized in node name")
	}

	// Should contain sanitized version
	if !strings.Contains(result, `node="node001"`) {
		t.Error("expected sanitized node name")
	}
}

func TestPushgatewayClient_PushSensors_MetricsFormat(t *testing.T) {
	var receivedBody string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body := make([]byte, 4096)
		n, _ := r.Body.Read(body)
		receivedBody = string(body[:n])
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewPushgatewayClientWithHTTPClient(server.URL, server.Client())

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify metric format follows Prometheus exposition format
	lines := strings.Split(strings.TrimSpace(receivedBody), "\n")
	if len(lines) != 2 {
		t.Errorf("expected 2 metric lines (value + status), got %d", len(lines))
	}

	// Check first line is the value metric
	if !strings.HasPrefix(lines[0], "qis_bmc_temperature_celsius{") {
		t.Errorf("expected first line to start with metric name, got %q", lines[0])
	}

	// Check second line is the status metric
	if !strings.HasPrefix(lines[1], "qis_bmc_sensor_status{") {
		t.Errorf("expected second line to start with status metric, got %q", lines[1])
	}
}

func TestPushgatewayClient_PushSensors_CustomJob(t *testing.T) {
	var receivedURL string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedURL = r.URL.Path
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewPushgatewayClientWithHTTPClient(server.URL, server.Client())
	client.SetJob("custom_collector")

	sensors := []model.BMCSensorReading{
		{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
	}

	err := client.PushSensors(context.Background(), "node001", sensors)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expectedURL := "/metrics/job/custom_collector/instance/node001"
	if receivedURL != expectedURL {
		t.Errorf("expected URL %q, got %q", expectedURL, receivedURL)
	}
}

func TestFormatSensorMetrics_FloatPrecision(t *testing.T) {
	sensors := []model.BMCSensorReading{
		{Name: "Sensor1", Value: 45.123456789, Unit: "Celsius", Status: "OK"},
		{Name: "Sensor2", Value: 0, Unit: "Celsius", Status: "OK"},
		{Name: "Sensor3", Value: -10.5, Unit: "Celsius", Status: "OK"},
		{Name: "Sensor4", Value: 1e10, Unit: "Watts", Status: "OK"},
	}

	result := formatSensorMetrics("node001", sensors)

	// Check that %g format is used (removes trailing zeros)
	if !strings.Contains(result, "45.123456789") {
		t.Error("expected full float precision for Sensor1")
	}

	// Check zero value
	if !strings.Contains(result, `sensor="Sensor2"} 0`) {
		t.Error("expected zero value for Sensor2")
	}

	// Check negative value
	if !strings.Contains(result, `sensor="Sensor3"} -10.5`) {
		t.Error("expected negative value for Sensor3")
	}

	// Check scientific notation handling
	if !strings.Contains(result, `sensor="Sensor4"} 1e+10`) {
		t.Log(result)
		t.Error("expected scientific notation for large value")
	}
}
