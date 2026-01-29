hpcg_work_dir:
  file.directory:
    - name: {{ pillar.get('work_dir', '/tmp/hpcg') }}
    - makedirs: True

hpcg_binary_check:
  cmd.run:
    - name: which hpcg || echo "HPCG binary not found"
    - require:
      - file: hpcg_work_dir
