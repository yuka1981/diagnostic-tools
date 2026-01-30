# HPCG Benchmark Orchestration
# Applied via: salt 'node-01' state.apply benchmark.hpcg pillar='{"run_id": "uuid", "work_dir": "/tmp/hpcg"}'

include:
  - benchmark.hpcg.prepare
  - benchmark.hpcg.execute
  - benchmark.hpcg.collect
