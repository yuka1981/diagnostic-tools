package mlc

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

const (
	DefaultInstallDir = "/opt/qct/utils/qis/software"
	DefaultModuleDir  = "/opt/qct/utils/qis/modulefiles"
)

var installVersionRegex = regexp.MustCompile(`v?(\d+\.\d+(?:\.\d+)?)`)

// InstallParams defines parameters for MLC installation.
type InstallParams struct {
	Tarball    string
	BinaryPath string // Relative path within tarball (e.g., "Linux/mlc")
	InstallDir string
	ModuleDir  string
	InstallID  string
}

// InstallResult contains the result of installation.
type InstallResult struct {
	Version        string
	InstallPath    string
	ModulePath     string
	ErrorMessage   string
	FailedStepName string
	FailedAtStep   int
	Success        bool
}

// InstallWorkflow manages the MLC installation process.
type InstallWorkflow struct {
	Runner ports.CommandRunner
}

// NewInstallWorkflow creates a new install workflow.
func NewInstallWorkflow(runner ports.CommandRunner) *InstallWorkflow {
	return &InstallWorkflow{Runner: runner}
}

// Run executes the installation workflow.
func (w *InstallWorkflow) Run(ctx context.Context, params *InstallParams) *InstallResult {
	// Step 1: Validate tarball
	if err := w.validateTarball(params.Tarball); err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: err.Error(),
			FailedAtStep: 1, FailedStepName: "Validate tarball",
		}
	}

	// Step 2: Extract to temp directory
	extractDir, err := w.extractTarball(params.Tarball)
	if err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Extract failed: %v", err),
			FailedAtStep: 2, FailedStepName: "Extract tarball",
		}
	}
	defer os.RemoveAll(extractDir)

	// Step 3: Detect version
	binaryPath := filepath.Join(extractDir, params.BinaryPath)
	version, err := w.detectVersion(binaryPath)
	if err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Version detection failed: %v", err),
			FailedAtStep: 3, FailedStepName: "Detect version",
		}
	}

	// Step 4: Install binary
	installPath := filepath.Join(params.InstallDir, fmt.Sprintf("mlc-%s", version))
	if err := w.installBinary(binaryPath, installPath); err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Install failed: %v", err),
			FailedAtStep: 4, FailedStepName: "Install binary",
		}
	}

	// Step 5: Generate modulefile
	modulePath := filepath.Join(params.ModuleDir, "mlc", version)
	if err := w.writeModulefile(version, installPath, modulePath); err != nil {
		return &InstallResult{
			Success: false, ErrorMessage: fmt.Sprintf("Modulefile creation failed: %v", err),
			FailedAtStep: 5, FailedStepName: "Generate modulefile",
		}
	}

	// Step 6: Update symlink (best effort, ignore errors)
	latestLink := filepath.Join(params.InstallDir, "mlc-latest")
	_ = os.Remove(latestLink) // Remove old symlink if exists
	_ = os.Symlink(installPath, latestLink)

	return &InstallResult{
		Success:     true,
		Version:     version,
		InstallPath: installPath,
		ModulePath:  modulePath,
	}
}

func (w *InstallWorkflow) validateTarball(path string) error {
	info, err := os.Stat(path)
	if os.IsNotExist(err) {
		return fmt.Errorf("tarball not found: %s", path)
	}
	if err != nil {
		return fmt.Errorf("cannot access tarball: %w", err)
	}
	if info.IsDir() {
		return fmt.Errorf("path is a directory, not a tarball: %s", path)
	}
	return nil
}

func (w *InstallWorkflow) extractTarball(tarballPath string) (string, error) {
	extractDir, err := os.MkdirTemp("", "mlc-extract-")
	if err != nil {
		return "", err
	}

	if err := w.doExtract(tarballPath, extractDir); err != nil {
		os.RemoveAll(extractDir)
		return "", err
	}

	return extractDir, nil
}

func (w *InstallWorkflow) doExtract(tarballPath, extractDir string) error {
	file, err := os.Open(tarballPath)
	if err != nil {
		return err
	}
	defer file.Close()

	gzr, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)
	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		if err := w.extractEntry(header, tr, extractDir); err != nil {
			return err
		}
	}
	return nil
}

func (w *InstallWorkflow) extractEntry(header *tar.Header, tr *tar.Reader, extractDir string) error {
	target := filepath.Join(extractDir, header.Name) //nolint:gosec // G305: path traversal checked below

	// Security: prevent path traversal
	if !strings.HasPrefix(target, filepath.Clean(extractDir)+string(os.PathSeparator)) {
		return nil
	}

	switch header.Typeflag {
	case tar.TypeDir:
		return os.MkdirAll(target, 0755)
	case tar.TypeReg:
		return w.extractFile(header, tr, target)
	}
	return nil
}

func (w *InstallWorkflow) extractFile(header *tar.Header, tr *tar.Reader, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
		return err
	}
	f, err := os.OpenFile(target, os.O_CREATE|os.O_RDWR, os.FileMode(header.Mode)) //nolint:gosec // G115: tar header mode is safe
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, tr)
	return err
}

func (w *InstallWorkflow) detectVersion(binaryPath string) (string, error) {
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		return "", fmt.Errorf("binary not found at: %s", binaryPath)
	}

	// Make binary executable (best effort)
	_ = os.Chmod(binaryPath, 0755)

	cmd := exec.Command(binaryPath, "--version")
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Try without --version flag (some versions just output on run)
		cmd = exec.Command(binaryPath)
		output, _ = cmd.CombinedOutput()
	}

	version := w.parseVersion(string(output))
	if version == "" {
		return "", fmt.Errorf("could not detect version from binary output")
	}

	return version, nil
}

func (w *InstallWorkflow) parseVersion(output string) string {
	match := installVersionRegex.FindStringSubmatch(output)
	if len(match) >= 2 {
		return match[1]
	}
	return ""
}

func (w *InstallWorkflow) installBinary(srcBinary, installDir string) error {
	if err := os.MkdirAll(installDir, 0755); err != nil {
		return fmt.Errorf("failed to create install directory: %w", err)
	}

	dstBinary := filepath.Join(installDir, "mlc")

	src, err := os.Open(srcBinary)
	if err != nil {
		return err
	}
	defer src.Close()

	dst, err := os.OpenFile(dstBinary, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
	if err != nil {
		return err
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		return err
	}

	return nil
}

func (w *InstallWorkflow) writeModulefile(version, installDir, modulePath string) error {
	moduleDir := filepath.Dir(modulePath)
	if err := os.MkdirAll(moduleDir, 0755); err != nil {
		return fmt.Errorf("failed to create modulefile directory: %w", err)
	}

	content := w.generateModulefile(version, installDir)

	return os.WriteFile(modulePath, []byte(content), 0644) //nolint:gosec // G306: modulefile needs to be readable by all users
}

func (w *InstallWorkflow) generateModulefile(version, installDir string) string {
	return fmt.Sprintf(`-- Intel Memory Latency Checker (MLC) v%s
-- Auto-generated modulefile

help([[Intel Memory Latency Checker (MLC) v%s
Memory subsystem benchmarking tool from Intel.
]])

whatis("Name: Intel MLC")
whatis("Version: %s")
whatis("Description: Memory subsystem benchmarking tool")

local base = "%s"

prepend_path("PATH", base)
`, version, version, version, installDir)
}
