# MLC Benchmark Orchestration
# Applied via: salt 'node-01' state.apply benchmark.mlc pillar='{"run_id": "uuid", "work_dir": "/tmp/mlc", "binary_path": "mlc", "profile": "quick"}'

include:
  - benchmark.mlc.prepare
  - benchmark.mlc.execute
  - benchmark.mlc.collect
