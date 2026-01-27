package mlc

import "testing"

func TestGetProfile(t *testing.T) {
	tests := []struct {
		name          string
		expectedTests []string
		expectError   bool
	}{
		{
			name:          "quick",
			expectedTests: []string{"idle_latency", "peak_injection_bandwidth"},
			expectError:   false,
		},
		{
			name:          "standard",
			expectedTests: []string{"latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth"},
			expectError:   false,
		},
		{
			name: "full",
			expectedTests: []string{
				"idle_latency", "loaded_latency", "latency_matrix",
				"bandwidth_matrix", "peak_injection_bandwidth", "c2c_latency",
			},
			expectError: false,
		},
		{
			name:          "numa",
			expectedTests: []string{"latency_matrix", "bandwidth_matrix", "c2c_latency"},
			expectError:   false,
		},
		{
			name:          "latency",
			expectedTests: []string{"idle_latency", "loaded_latency", "c2c_latency"},
			expectError:   false,
		},
		{
			name:        "invalid",
			expectError: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			profile, err := GetProfile(tc.name)

			if tc.expectError {
				if err == nil {
					t.Error("expected error, got nil")
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if len(profile.Tests) != len(tc.expectedTests) {
				t.Errorf("profile.Tests length = %d, want %d", len(profile.Tests), len(tc.expectedTests))
			}

			for i, test := range tc.expectedTests {
				if profile.Tests[i] != test {
					t.Errorf("profile.Tests[%d] = %s, want %s", i, profile.Tests[i], test)
				}
			}
		})
	}
}

func TestDefaultProfile(t *testing.T) {
	profile := DefaultProfile()
	if profile.Name != "quick" {
		t.Errorf("DefaultProfile().Name = %s, want quick", profile.Name)
	}
}

func TestListProfiles(t *testing.T) {
	names := ListProfiles()

	if len(names) != 5 {
		t.Errorf("ListProfiles() returned %d names, want 5", len(names))
	}

	expectedProfiles := map[string]bool{
		"quick":    false,
		"standard": false,
		"full":     false,
		"numa":     false,
		"latency":  false,
	}

	for _, name := range names {
		if _, ok := expectedProfiles[name]; !ok {
			t.Errorf("unexpected profile name: %s", name)
		}
		expectedProfiles[name] = true
	}

	for name, found := range expectedProfiles {
		if !found {
			t.Errorf("missing expected profile: %s", name)
		}
	}
}
