package hpcg

import (
	"strings"
	"testing"
)

func TestGenerateConfig(t *testing.T) {
	params := ConfigParams{
		NX:             104,
		NY:             104,
		NZ:             104,
		RunTimeSeconds: 60,
	}

	expectedContent := `HPCG benchmark input file
Sandia National Laboratories; University of Tennessee, Knoxville
104 104 104
60`

	content := GenerateConfig(params)

	// Normalize line endings for comparison
	content = strings.TrimSpace(content)
	expectedContent = strings.TrimSpace(expectedContent)

	if content != expectedContent {
		t.Errorf("expected content:\n%q\n\ngot:\n%q", expectedContent, content)
	}
}

func TestGenerateConfig_DifferentValues(t *testing.T) {
	params := ConfigParams{
		NX:             128,
		NY:             128,
		NZ:             128,
		RunTimeSeconds: 120,
	}

	expectedLine3 := "128 128 128"
	expectedLine4 := "120"

	content := GenerateConfig(params)
	lines := strings.Split(strings.TrimSpace(content), "\n")

	if len(lines) < 4 {
		t.Fatalf("expected at least 4 lines, got %d", len(lines))
	}

	if strings.TrimSpace(lines[2]) != expectedLine3 {
		t.Errorf("expected line 3 to be %q, got %q", expectedLine3, lines[2])
	}
	if strings.TrimSpace(lines[3]) != expectedLine4 {
		t.Errorf("expected line 4 to be %q, got %q", expectedLine4, lines[3])
	}
}
