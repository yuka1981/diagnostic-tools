# Results are returned inline from the execute module
# Artifacts can be pushed to master via cp.push
push_hpcg_artifacts:
  module.run:
    - cp.push_dir:
      - path: {{ pillar.get('work_dir', '/tmp/hpcg') }}
      - glob: "*"
    - require:
      - module: run_hpcg
