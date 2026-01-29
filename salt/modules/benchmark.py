"""
Salt custom execution module for benchmark execution.
Handles HPCG and MLC benchmark lifecycle.

Usage via salt-api:
    salt 'minion-id' benchmark.run_hpcg work_dir=/tmp/hpcg run_id=uuid
    salt 'minion-id' benchmark.run_mlc work_dir=/tmp/mlc run_id=uuid
    salt 'minion-id' benchmark.cancel
"""

import json
import os
import re
import signal
import subprocess
import time


__virtualname__ = 'benchmark'


def __virtual__():
    return __virtualname__


def run_hpcg(work_dir='/tmp/hpcg', run_id=None, **kwargs):
    """Run HPCG benchmark and return structured results."""
    start_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())

    result = _run_command(
        ['hpcg'],
        cwd=work_dir,
        timeout=kwargs.get('timeout', 3600)
    )

    end_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    status = 'PASS' if result['retcode'] == 0 else 'FAIL'

    return {
        'status': status,
        'metrics': _parse_hpcg_metrics(result['stdout']),
        'start_time': start_time,
        'end_time': end_time,
        'log_content': result['stdout'] + result['stderr'],
        'error_message': result['stderr'] if status == 'FAIL' else None,
        'run_id': run_id,
        'artifacts': _find_artifacts(work_dir),
    }


def run_mlc(work_dir='/tmp/mlc', run_id=None, binary_path='mlc', profile='quick', **kwargs):
    """Run MLC benchmark and return structured results."""
    start_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())

    cmd = [binary_path]
    if profile == 'quick':
        cmd.extend(['--idle_latency', '--peak_injection_bandwidth'])

    result = _run_command(cmd, cwd=work_dir, timeout=kwargs.get('timeout', 3600))

    end_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    status = 'PASS' if result['retcode'] == 0 else 'FAIL'

    return {
        'status': status,
        'metrics': _parse_mlc_metrics(result['stdout']),
        'start_time': start_time,
        'end_time': end_time,
        'log_content': result['stdout'] + result['stderr'],
        'error_message': result['stderr'] if status == 'FAIL' else None,
        'run_id': run_id,
        'artifacts': _find_artifacts(work_dir),
    }


def cancel():
    """Cancel a running benchmark process."""
    pid = _find_benchmark_pid()
    if pid is None:
        return {'success': False, 'error': 'No benchmark process found'}

    try:
        os.kill(pid, signal.SIGTERM)
        return {'success': True, 'pid': pid}
    except ProcessLookupError:
        return {'success': False, 'error': f'Process {pid} not found'}
    except PermissionError:
        return {'success': False, 'error': f'Permission denied for PID {pid}'}


def _run_command(cmd, cwd=None, timeout=3600):
    """Run a command and capture output."""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True,
            cwd=cwd, timeout=timeout
        )
        return {
            'retcode': proc.returncode,
            'stdout': proc.stdout,
            'stderr': proc.stderr,
        }
    except subprocess.TimeoutExpired:
        return {
            'retcode': -1,
            'stdout': '',
            'stderr': f'Command timed out after {timeout}s',
        }
    except FileNotFoundError as e:
        return {
            'retcode': -1,
            'stdout': '',
            'stderr': str(e),
        }


def _find_benchmark_pid():
    """Find a running benchmark process PID."""
    try:
        result = subprocess.run(
            ['pgrep', '-f', '(hpcg|mlc)'],
            capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return int(result.stdout.strip().splitlines()[0])
    except (ValueError, FileNotFoundError):
        pass
    return None


def _parse_hpcg_metrics(stdout):
    """Parse HPCG output for metrics."""
    metrics = {}
    gflops_match = re.search(r'GFLOP/s:\s+([\d.]+)', stdout)
    if gflops_match:
        metrics['gflops'] = float(gflops_match.group(1))
    return metrics


def _parse_mlc_metrics(stdout):
    """Parse MLC output for metrics."""
    metrics = {}
    latency_match = re.search(r'Each iteration took\s+([\d.]+)\s+', stdout)
    if latency_match:
        metrics['idle_latency_ns'] = float(latency_match.group(1))
    return metrics


def _find_artifacts(work_dir):
    """Find artifact files in the work directory."""
    artifacts = []
    if not os.path.isdir(work_dir):
        return artifacts
    for f in os.listdir(work_dir):
        filepath = os.path.join(work_dir, f)
        if os.path.isfile(filepath) and f.endswith(('.txt', '.yaml', '.log', '.dat')):
            artifacts.append(filepath)
    return artifacts
