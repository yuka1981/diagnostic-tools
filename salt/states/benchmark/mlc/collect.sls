push_mlc_artifacts:
  module.run:
    - cp.push_dir:
      - path: {{ pillar.get('work_dir', '/tmp/mlc') }}
      - glob: "*"
    - require:
      - module: run_mlc
