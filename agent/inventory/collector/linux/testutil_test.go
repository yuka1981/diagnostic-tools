package linux

import (
	"context"
)

// MockCommandRunner mocks the CommandRunner interface for tests.
type MockCommandRunner struct {
	Err    error
	Output string
}

func (m *MockCommandRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	return []byte(m.Output), m.Err
}
