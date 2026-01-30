mlc_work_dir:
  file.directory:
    - name: {{ pillar.get('work_dir', '/tmp/mlc') }}
    - makedirs: True

mlc_binary_check:
  cmd.run:
    - name: "which '{{ pillar.get('binary_path', 'mlc') }}'"
    - require:
      - file: mlc_work_dir
