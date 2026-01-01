package hpcg

import (
	"fmt"
	"strings"
)

// ConfigParams holds the configuration parameters for HPCG benchmark.
type ConfigParams struct {
	NX             int
	NY             int
	NZ             int
	RunTimeSeconds int
}

// GenerateConfig generates the content of hpcg.dat based on the provided parameters.
func GenerateConfig(params ConfigParams) string {
	var sb strings.Builder
	sb.WriteString("HPCG benchmark input file\n")
	sb.WriteString("Sandia National Laboratories; University of Tennessee, Knoxville\n")
	sb.WriteString(fmt.Sprintf("%d %d %d\n", params.NX, params.NY, params.NZ))
	sb.WriteString(fmt.Sprintf("%d\n", params.RunTimeSeconds))
	return sb.String()
}
