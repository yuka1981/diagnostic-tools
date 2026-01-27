package mlc

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// MinHugepages is the minimum number of hugepages required for MLC.
const MinHugepages = 1000

// hugepagesPath is the path to the hugepages count file.
// This is a variable to allow testing with mock files.
var hugepagesPath = "/proc/sys/vm/nr_hugepages"

// CheckHugepages verifies that sufficient hugepages are allocated.
// Returns nil if hugepages are sufficient or if the check should be skipped
// (e.g., on non-Linux systems where the procfs file doesn't exist).
// Returns an actionable error if hugepages are insufficient.
func CheckHugepages(minRequired int) error {
	content, err := os.ReadFile(hugepagesPath)
	if err != nil {
		// File doesn't exist - skip gracefully (non-Linux or missing procfs)
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("failed to read hugepages count: %w", err)
	}

	// Parse the count
	countStr := strings.TrimSpace(string(content))
	count, err := strconv.Atoi(countStr)
	if err != nil {
		return fmt.Errorf("failed to parse hugepages count: %w", err)
	}

	// Check if sufficient
	if count < minRequired {
		return fmt.Errorf("Hugepages not configured (found: %d, required: %d)\n\nFix: echo 4000 > /proc/sys/vm/nr_hugepages (requires root)", count, minRequired)
	}

	return nil
}
