run_mlc:
  module.run:
    - benchmark.run_mlc:
      - work_dir: {{ pillar.get('work_dir', '/tmp/mlc') }}
      - run_id: {{ pillar.get('run_id', '') }}
      - binary_path: {{ pillar.get('binary_path', 'mlc') }}
      - profile: {{ pillar.get('profile', 'quick') }}
    - require:
      - cmd: mlc_binary_check
