package main

import (
	"os"

	"gopkg.in/yaml.v3"
)

// Config holds BMC collector configuration.
type Config struct {
	ServerURL     string `yaml:"server_url"`     // Rails API URL
	APIToken      string `yaml:"api_token"`      // Authentication token
	PrometheusURL string `yaml:"prometheus_url"` // Pushgateway URL
	LogFile       string `yaml:"log_file"`       // Log file path
	LogLevel      string `yaml:"log_level"`      // debug, info, warn, error
}

// loadConfig loads configuration from a YAML file.
func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}
