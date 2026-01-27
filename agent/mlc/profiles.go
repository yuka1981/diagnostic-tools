package mlc

import "fmt"

// Profile defines a set of MLC tests to run.
type Profile struct {
	Name        string
	Description string
	Tests       []string
}

// Predefined profiles for common use cases.
var profiles = map[string]Profile{
	"quick": {
		Name:        "quick",
		Description: "Fast health check (~4 min)",
		Tests:       []string{"idle_latency", "peak_injection_bandwidth"},
	},
	"standard": {
		Name:        "standard",
		Description: "Regular characterization (~6 min)",
		Tests:       []string{"latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth"},
	},
	"full": {
		Name:        "full",
		Description: "Complete characterization (~15 min)",
		Tests:       []string{"idle_latency", "loaded_latency", "latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth", "c2c_latency"},
	},
	"numa": {
		Name:        "numa",
		Description: "NUMA topology focus (~5 min)",
		Tests:       []string{"latency_matrix", "bandwidth_matrix", "c2c_latency"},
	},
	"latency": {
		Name:        "latency",
		Description: "Latency-sensitive workload tuning (~8 min)",
		Tests:       []string{"idle_latency", "loaded_latency", "c2c_latency"},
	},
}

// GetProfile returns the profile with the given name.
func GetProfile(name string) (Profile, error) {
	profile, ok := profiles[name]
	if !ok {
		return Profile{}, fmt.Errorf("unknown profile: %s", name)
	}
	return profile, nil
}

// DefaultProfile returns the default profile (quick).
func DefaultProfile() Profile {
	return profiles["quick"]
}

// ListProfiles returns all available profile names.
func ListProfiles() []string {
	names := make([]string, 0, len(profiles))
	for name := range profiles {
		names = append(names, name)
	}
	return names
}
