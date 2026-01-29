import json
import subprocess
from unittest import mock

import pytest

# We test the module functions directly
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import inventory


class TestCollectDmi:
    SAMPLE_DMIDECODE_BIOS = """
BIOS Information
\tVendor: American Megatrends Inc.
\tVersion: 3.3a
\tRelease Date: 01/15/2024
"""

    SAMPLE_DMIDECODE_SYSTEM = """
System Information
\tManufacturer: QCT
\tProduct Name: QuantaPlex T42S-2U
\tSerial Number: ABC123
"""

    SAMPLE_DMIDECODE_BASEBOARD = """
Base Board Information
\tManufacturer: QCT
\tProduct Name: S6Q
"""

    @mock.patch('inventory._run_dmidecode')
    def test_collect_dmi_returns_structured_data(self, mock_run):
        mock_run.side_effect = lambda t: {
            'bios': self.SAMPLE_DMIDECODE_BIOS,
            'system': self.SAMPLE_DMIDECODE_SYSTEM,
            'baseboard': self.SAMPLE_DMIDECODE_BASEBOARD,
        }[t]

        result = inventory.collect_dmi()

        assert result['bios']['vendor'] == 'American Megatrends Inc.'
        assert result['system']['manufacturer'] == 'QCT'
        assert result['system']['product_name'] == 'QuantaPlex T42S-2U'
        assert result['baseboard']['manufacturer'] == 'QCT'

    @mock.patch('inventory._run_dmidecode')
    def test_collect_dmi_handles_missing_dmidecode(self, mock_run):
        mock_run.side_effect = FileNotFoundError("dmidecode not found")

        result = inventory.collect_dmi()
        assert result == {'error': 'dmidecode not found'}


class TestCollectNuma:
    @mock.patch('inventory._read_file')
    @mock.patch('inventory._list_numa_nodes')
    def test_collect_numa_returns_topology(self, mock_list, mock_read):
        mock_list.return_value = ['node0', 'node1']
        mock_read.side_effect = lambda path: {
            '/sys/devices/system/node/node0/cpulist': '0-19',
            '/sys/devices/system/node/node0/meminfo': 'Node 0 MemTotal:       131072000 kB',
            '/sys/devices/system/node/node1/cpulist': '20-39',
            '/sys/devices/system/node/node1/meminfo': 'Node 1 MemTotal:       131072000 kB',
        }.get(path, '')

        result = inventory.collect_numa()

        assert result['node_count'] == 2
        assert result['nodes']['0']['cpulist'] == '0-19'
        assert result['nodes']['1']['cpulist'] == '20-39'
        assert result['nodes']['0']['memory_kb'] == 131072000

    @mock.patch('inventory._list_numa_nodes')
    def test_collect_numa_handles_no_numa(self, mock_list):
        mock_list.return_value = []

        result = inventory.collect_numa()
        assert result['node_count'] == 0
        assert result['nodes'] == {}


class TestCollectNetworkV2:
    SAMPLE_LSHW_OUTPUT = json.dumps([
        {
            "id": "network:0",
            "class": "network",
            "handle": "PCI:0000:3b:00.0",
            "description": "Ethernet interface",
            "product": "Ethernet Controller XXV710",
            "vendor": "Intel Corporation",
            "logicalname": "eth0",
            "serial": "aa:bb:cc:dd:ee:ff",
            "configuration": {
                "driver": "i40e",
                "speed": "25Gbit/s",
                "link": "yes"
            }
        }
    ])

    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_returns_devices(self, mock_run):
        mock_run.return_value = self.SAMPLE_LSHW_OUTPUT

        result = inventory.collect_network_v2()

        assert len(result['devices']) == 1
        dev = result['devices'][0]
        assert dev['name'] == 'eth0'
        assert dev['driver'] == 'i40e'
        assert dev['speed'] == '25Gbit/s'
        assert dev['mac'] == 'aa:bb:cc:dd:ee:ff'
        assert dev['vendor'] == 'Intel Corporation'

    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_handles_lshw_failure(self, mock_run):
        mock_run.side_effect = FileNotFoundError("lshw not found")

        result = inventory.collect_network_v2()
        assert result == {'error': 'lshw not found'}
