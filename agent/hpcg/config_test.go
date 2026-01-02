package hpcg

import (
	"testing"
)

func TestGenerateConfig(t *testing.T) {
	testCases := []struct {
		name   string
		want   string
		params ConfigParams
	}{
		{
			name: "default values",
			params: ConfigParams{
				NX:             104,
				NY:             104,
				NZ:             104,
				RunTimeSeconds: 60,
			},
			want: "HPCG benchmark input file\n" +
				"Sandia National Laboratories; University of Tennessee, Knoxville\n" +
				"104 104 104\n" +
				"60\n",
		},
		{
			name: "different values",
			params: ConfigParams{
				NX:             128,
				NY:             128,
				NZ:             128,
				RunTimeSeconds: 120,
			},
			want: "HPCG benchmark input file\n" +
				"Sandia National Laboratories; University of Tennessee, Knoxville\n" +
				"128 128 128\n" +
				"120\n",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			got := GenerateConfig(tc.params)
			if got != tc.want {
				t.Errorf("expected content:\n%q\n\ngot:\n%q", tc.want, got)
			}
		})
	}
}
