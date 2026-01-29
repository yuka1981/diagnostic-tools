from unittest import mock
import os
import sys
import signal
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import benchmark


class TestRunHpcg:
    @mock.patch('benchmark._run_command')
    def test_run_hpcg_returns_results(self, mock_run):
        mock_run.return_value = {
            'retcode': 0,
            'stdout': 'HPCG result is VALID\nGFLOP/s: 45.67',
            'stderr': '',
        }

        result = benchmark.run_hpcg(
            work_dir='/tmp/hpcg',
            run_id='test-uuid-123'
        )

        assert result['status'] == 'PASS'
        assert 'metrics' in result
        assert result['run_id'] == 'test-uuid-123'

    @mock.patch('benchmark._run_command')
    def test_run_hpcg_handles_failure(self, mock_run):
        mock_run.return_value = {
            'retcode': 1,
            'stdout': '',
            'stderr': 'Error: binary not found',
        }

        result = benchmark.run_hpcg(work_dir='/tmp/hpcg', run_id='test-uuid')
        assert result['status'] == 'FAIL'
        assert 'error_message' in result


class TestCancel:
    @mock.patch('os.kill')
    @mock.patch('benchmark._find_benchmark_pid')
    def test_cancel_sends_sigterm(self, mock_find, mock_kill):
        mock_find.return_value = 12345

        result = benchmark.cancel()

        mock_kill.assert_called_once_with(12345, signal.SIGTERM)
        assert result['success'] is True

    @mock.patch('benchmark._find_benchmark_pid')
    def test_cancel_returns_error_when_no_process(self, mock_find):
        mock_find.return_value = None

        result = benchmark.cancel()
        assert result['success'] is False
