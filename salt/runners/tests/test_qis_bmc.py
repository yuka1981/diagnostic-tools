"""Tests for qis_bmc Salt runner module."""

import unittest
from unittest.mock import patch, MagicMock
import sys
import os

# Ensure a mock 'requests' module is available before importing qis_bmc,
# since requests may not be installed in the test environment.
mock_requests_module = MagicMock()
sys.modules.setdefault("requests", mock_requests_module)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import qis_bmc

# Ensure qis_bmc.requests points to our mock module
if qis_bmc.requests is None:
    qis_bmc.requests = mock_requests_module


class TestProtocolDetection(unittest.TestCase):
    """Test BMC protocol auto-detection logic."""

    def setUp(self):
        # Clear protocol cache between tests
        qis_bmc._protocol_cache.clear()

    @patch("qis_bmc.requests.get")
    def test_detects_redfish_when_available(self, mock_get):
        mock_get.return_value = MagicMock(status_code=200)
        result = qis_bmc._detect_protocol("10.0.0.1", "admin", "pass", True)
        self.assertEqual(result, "redfish")

    @patch("qis_bmc.subprocess.run")
    @patch("qis_bmc.requests.get", side_effect=Exception("Connection refused"))
    def test_falls_back_to_ipmi(self, mock_get, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout="Device ID : 32")
        result = qis_bmc._detect_protocol("10.0.0.1", "admin", "pass", True)
        self.assertEqual(result, "ipmi")

    @patch("qis_bmc.subprocess.run")
    @patch("qis_bmc.requests.get", side_effect=Exception("Connection refused"))
    def test_returns_none_when_both_fail(self, mock_get, mock_run):
        mock_run.return_value = MagicMock(returncode=1, stderr="Error")
        result = qis_bmc._detect_protocol("10.0.0.1", "admin", "pass", True)
        self.assertIsNone(result)


class TestSensorParsing(unittest.TestCase):
    """Test IPMI SDR output parsing."""

    def test_parses_temperature_sdr(self):
        sdr_output = (
            "CPU1 Temp        | 52 degrees C      | ok\n"
            "Inlet Temp       | 24 degrees C      | ok\n"
            "FAN1             | 4200 RPM          | ok\n"
            "Total Power      | 450 Watts         | ok\n"
        )
        readings = qis_bmc._parse_ipmi_sdr(sdr_output)
        temps = [r for r in readings if r["type"] == "temperature"]
        fans = [r for r in readings if r["type"] == "fan"]
        power = [r for r in readings if r["type"] == "power"]
        self.assertEqual(len(temps), 2)
        self.assertEqual(temps[0]["value"], 52.0)
        self.assertEqual(len(fans), 1)
        self.assertEqual(fans[0]["value"], 4200.0)
        self.assertEqual(len(power), 1)


if __name__ == "__main__":
    unittest.main()
