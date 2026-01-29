run_hpcg:
  module.run:
    - benchmark.run_hpcg:
      - work_dir: {{ pillar.get('work_dir', '/tmp/hpcg') }}
      - run_id: {{ pillar.get('run_id', '') }}
    - require:
      - cmd: hpcg_binary_check
