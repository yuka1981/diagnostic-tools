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

    SAMPLE_DMIDECODE_MEMORY = """
Memory Device
\tTotal Width: 72 bits
\tData Width: 64 bits
\tSize: 32 GB
\tForm Factor: DIMM
\tLocator: DIMM_A0
\tBank Locator: CPU 0 Channel 0
\tType: DDR4
\tSpeed: 3200 MT/s
\tConfigured Memory Speed: 2933 MT/s
\tManufacturer: Samsung
\tSerial Number: 1A2B3C4D
\tPart Number: M393A4K40DB3-CWE

Memory Device
\tTotal Width: 72 bits
\tData Width: 64 bits
\tSize: 32 GB
\tForm Factor: DIMM
\tLocator: DIMM_B0
\tBank Locator: CPU 0 Channel 1
\tType: DDR4
\tSpeed: 3200 MT/s
\tConfigured Memory Speed: 2933 MT/s
\tManufacturer: Samsung
\tSerial Number: 5E6F7G8H
\tPart Number: M393A4K40DB3-CWE
"""

    @mock.patch('inventory._run_dmidecode')
    def test_collect_dmi_returns_structured_data(self, mock_run):
        mock_run.side_effect = lambda t: {
            'bios': self.SAMPLE_DMIDECODE_BIOS,
            'system': self.SAMPLE_DMIDECODE_SYSTEM,
            'baseboard': self.SAMPLE_DMIDECODE_BASEBOARD,
            'memory': self.SAMPLE_DMIDECODE_MEMORY,
        }[t]

        result = inventory.collect_dmi()

        assert result['bios']['vendor'] == 'American Megatrends Inc.'
        assert result['system']['manufacturer'] == 'QCT'
        assert result['system']['product_name'] == 'QuantaPlex T42S-2U'
        assert result['baseboard']['manufacturer'] == 'QCT'
        assert 'memory' in result
        assert isinstance(result['memory'], list)

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


class TestParseDmiMemory:
    SAMPLE_OUTPUT = """
# dmidecode 3.3
Getting SMBIOS data from sysfs.
SMBIOS 3.3.0 present.

Handle 0x0044, DMI type 17, 92 bytes
Memory Device
\tTotal Width: 72 bits
\tData Width: 64 bits
\tSize: 32 GB
\tForm Factor: DIMM
\tLocator: DIMM_A0
\tBank Locator: CPU 0 Channel 0
\tType: DDR4
\tSpeed: 3200 MT/s
\tConfigured Memory Speed: 2933 MT/s
\tManufacturer: Samsung
\tSerial Number: 1A2B3C4D
\tPart Number: M393A4K40DB3-CWE

Handle 0x0045, DMI type 17, 92 bytes
Memory Device
\tTotal Width: 72 bits
\tData Width: 64 bits
\tSize: No Module Installed
\tForm Factor: DIMM
\tLocator: DIMM_A1
\tBank Locator: CPU 0 Channel 1
\tType: Unknown
"""

    def test_parse_dmi_memory_returns_list_of_devices(self):
        result = inventory._parse_dmi_memory(self.SAMPLE_OUTPUT)
        assert isinstance(result, list)
        assert len(result) == 2
        assert result[0]['size'] == '32 GB'
        assert result[0]['locator'] == 'DIMM_A0'
        assert result[0]['bank_locator'] == 'CPU 0 Channel 0'
        assert result[0]['type'] == 'DDR4'
        assert result[0]['speed'] == '3200 MT/s'
        assert result[0]['configured_memory_speed'] == '2933 MT/s'
        assert result[0]['manufacturer'] == 'Samsung'
        assert result[0]['serial_number'] == '1A2B3C4D'
        assert result[1]['size'] == 'No Module Installed'
        assert result[1]['locator'] == 'DIMM_A1'
        assert result[1]['bank_locator'] == 'CPU 0 Channel 1'

    def test_parse_dmi_memory_handles_empty_output(self):
        result = inventory._parse_dmi_memory('')
        assert result == []

    def test_parse_dmi_memory_handles_no_devices(self):
        result = inventory._parse_dmi_memory('# dmidecode 3.3\nSMBIOS 3.3.0 present.\n')
        assert result == []


class TestCollectMeminfo:
    SAMPLE_MEMINFO = """\
MemTotal:       2113698482 kB
MemFree:        1800000000 kB
MemAvailable:   1900000000 kB
Buffers:          1234567 kB
Cached:          50000000 kB
SwapTotal:       4194304 kB
SwapFree:        4194304 kB
HugePages_Total:       0
"""

    @mock.patch('inventory._read_file')
    def test_collect_meminfo_parses_proc_meminfo(self, mock_read):
        mock_read.return_value = self.SAMPLE_MEMINFO

        result = inventory.collect_meminfo()

        assert result['MemTotal'] == 2113698482
        assert result['MemAvailable'] == 1900000000
        assert result['MemFree'] == 1800000000
        assert result['SwapTotal'] == 4194304
        assert result['HugePages_Total'] == 0

    def test_parse_proc_meminfo_handles_empty(self):
        result = inventory._parse_proc_meminfo('')
        assert result == {}

    def test_parse_proc_meminfo_handles_plain_integers(self):
        result = inventory._parse_proc_meminfo('HugePages_Total:       0\n')
        assert result['HugePages_Total'] == 0
