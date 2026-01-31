import json
import subprocess
from unittest import mock

import pytest

# We test the module functions directly
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '_modules'))

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

    @mock.patch('inventory._get_ip_addresses', return_value=['192.168.1.10/24'])
    @mock.patch('inventory._get_master', return_value=None)
    @mock.patch('inventory._detect_interface_type', return_value='ethernet')
    @mock.patch('inventory._read_sysfs_attr', return_value='up')
    @mock.patch('inventory._list_sysfs_interfaces', return_value=['eth0'])
    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_returns_devices(
        self, mock_lshw, mock_sysfs_list, mock_sysfs_attr,
        mock_type, mock_master, mock_ip,
    ):
        mock_lshw.return_value = self.SAMPLE_LSHW_OUTPUT

        result = inventory.collect_network_v2()

        assert len(result['devices']) == 1
        dev = result['devices'][0]
        assert dev['name'] == 'eth0'
        assert dev['driver'] == 'i40e'
        assert dev['speed'] == '25Gbit/s'
        assert dev['mac'] == 'aa:bb:cc:dd:ee:ff'
        assert dev['vendor'] == 'Intel Corporation'
        # New fields
        assert dev['model'] == 'Ethernet Controller XXV710'
        assert dev['pci_address'] == '0000:3b:00.0'
        assert dev['oper_state'] == 'up'
        assert dev['type'] == 'ethernet'
        assert dev['ip_addresses'] == ['192.168.1.10/24']
        assert dev['master'] is None

    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_handles_lshw_failure(self, mock_run):
        mock_run.side_effect = FileNotFoundError("lshw not found")

        result = inventory.collect_network_v2()
        assert result == {'error': 'lshw not found'}

    @mock.patch('inventory._get_ip_addresses', return_value=[])
    @mock.patch('inventory._get_master', return_value='bond0')
    @mock.patch('inventory._detect_interface_type', return_value='ethernet')
    @mock.patch('inventory._read_sysfs_attr')
    @mock.patch('inventory._read_sysfs_speed', return_value='1Gbit/s')
    @mock.patch('inventory._get_pci_address_from_sysfs', return_value='0000:01:00.0')
    @mock.patch('inventory._get_driver_name', return_value='ixgbe')
    @mock.patch('inventory._list_sysfs_interfaces', return_value=['eth0', 'eth1', 'lo'])
    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_discovers_sysfs_only_interfaces(
        self, mock_lshw, mock_sysfs_list, mock_driver, mock_pci,
        mock_speed, mock_sysfs_attr, mock_type, mock_master, mock_ip,
    ):
        """Interfaces found in sysfs but not in lshw should be added."""
        mock_lshw.return_value = self.SAMPLE_LSHW_OUTPUT
        # _read_sysfs_attr is called for operstate and address
        mock_sysfs_attr.side_effect = lambda iface, attr: {
            'operstate': 'up',
            'address': '11:22:33:44:55:66',
        }.get(attr, None)

        result = inventory.collect_network_v2()

        names = [d['name'] for d in result['devices']]
        assert 'eth0' in names
        assert 'eth1' in names
        # loopback should be excluded
        assert 'lo' not in names

        # eth1 should be the sysfs-only device
        eth1 = next(d for d in result['devices'] if d['name'] == 'eth1')
        assert eth1['driver'] == 'ixgbe'
        assert eth1['pci_address'] == '0000:01:00.0'
        assert eth1['speed'] == '1Gbit/s'
        assert eth1['master'] == 'bond0'

    @mock.patch('inventory._get_ip_addresses', return_value=[])
    @mock.patch('inventory._get_master', return_value=None)
    @mock.patch('inventory._detect_interface_type', return_value='ethernet')
    @mock.patch('inventory._read_sysfs_attr', return_value='up')
    @mock.patch('inventory._list_sysfs_interfaces', return_value=['eth0'])
    @mock.patch('inventory._run_lshw')
    def test_collect_network_v2_normalises_pci_handle(
        self, mock_lshw, mock_sysfs_list, mock_sysfs_attr,
        mock_type, mock_master, mock_ip,
    ):
        """PCI handle 'PCI:0000:3b:00.0' should become '0000:3b:00.0'."""
        mock_lshw.return_value = self.SAMPLE_LSHW_OUTPUT

        result = inventory.collect_network_v2()
        dev = result['devices'][0]
        assert dev['pci_address'] == '0000:3b:00.0'
        assert 'pci_slot' not in dev


class TestDetectInterfaceType:
    @mock.patch('os.path.isfile', return_value=False)
    @mock.patch('os.path.isdir', return_value=False)
    @mock.patch('inventory._read_file', return_value='32\n')
    def test_infiniband(self, mock_read, mock_isdir, mock_isfile):
        assert inventory._detect_interface_type('ib0') == 'infiniband'

    @mock.patch('os.path.isfile', return_value=False)
    @mock.patch('os.path.isdir', return_value=False)
    @mock.patch('inventory._read_file', return_value='1\n')
    def test_ethernet(self, mock_read, mock_isdir, mock_isfile):
        assert inventory._detect_interface_type('eth0') == 'ethernet'

    @mock.patch('os.path.isfile', return_value=False)
    @mock.patch('os.path.isdir')
    @mock.patch('inventory._read_file', return_value='1\n')
    def test_bridge(self, mock_read, mock_isdir, mock_isfile):
        mock_isdir.side_effect = lambda p: 'bridge' in p
        assert inventory._detect_interface_type('br0') == 'bridge'

    @mock.patch('os.path.isfile', return_value=False)
    @mock.patch('os.path.isdir')
    @mock.patch('inventory._read_file', return_value='1\n')
    def test_bond(self, mock_read, mock_isdir, mock_isfile):
        mock_isdir.side_effect = lambda p: 'bonding' in p
        assert inventory._detect_interface_type('bond0') == 'bond'

    @mock.patch('os.path.isfile')
    @mock.patch('os.path.isdir', return_value=False)
    @mock.patch('inventory._read_file', return_value='1\n')
    def test_vlan(self, mock_read, mock_isdir, mock_isfile):
        mock_isfile.side_effect = lambda p: '/proc/net/vlan/' in p
        assert inventory._detect_interface_type('eth0.100') == 'vlan'


class TestGetIpAddressesJson:
    @mock.patch('subprocess.run')
    def test_parses_json_output(self, mock_run):
        mock_run.return_value = mock.Mock(
            stdout=json.dumps([{
                "addr_info": [
                    {"family": "inet", "local": "192.168.1.10", "prefixlen": 24},
                    {"family": "inet6", "local": "fe80::1", "prefixlen": 64},
                ]
            }]),
            returncode=0,
        )
        result = inventory._get_ip_addresses_json('eth0')
        assert result == ['192.168.1.10/24', 'fe80::1/64']

    @mock.patch('subprocess.run', side_effect=FileNotFoundError)
    def test_returns_none_on_missing_ip_command(self, mock_run):
        assert inventory._get_ip_addresses_json('eth0') is None

    @mock.patch('subprocess.run', side_effect=subprocess.CalledProcessError(1, 'ip'))
    def test_returns_none_on_error(self, mock_run):
        assert inventory._get_ip_addresses_json('eth0') is None


class TestGetIpAddressesFallback:
    IP_ADDR_SHOW_OUTPUT = """\
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0
    inet6 fe80::1/64 scope link
"""

    @mock.patch('subprocess.run')
    def test_parses_text_output(self, mock_run):
        mock_run.return_value = mock.Mock(
            stdout=self.IP_ADDR_SHOW_OUTPUT, returncode=0,
        )
        result = inventory._get_ip_addresses_fallback('eth0')
        assert '10.0.0.5/24' in result
        assert 'fe80::1/64' in result

    @mock.patch('inventory._read_file', return_value='')
    @mock.patch('subprocess.run', side_effect=FileNotFoundError)
    def test_returns_empty_on_failure(self, mock_run, mock_read):
        result = inventory._get_ip_addresses_fallback('eth0')
        assert result == []


class TestParseProcIfInet6:
    SAMPLE = "fe800000000000000000000000000001 02 0a 20 80    eth0\n"

    @mock.patch('inventory._read_file', return_value=SAMPLE)
    def test_parses_ipv6_addresses(self, mock_read):
        result = inventory._parse_proc_if_inet6('eth0')
        assert len(result) == 1
        assert result[0] == 'fe80:0000:0000:0000:0000:0000:0000:0001/10'

    @mock.patch('inventory._read_file', return_value='')
    def test_handles_empty(self, mock_read):
        assert inventory._parse_proc_if_inet6('eth0') == []


class TestReadSysfsSpeed:
    @mock.patch('inventory._read_file', return_value='25000\n')
    def test_25g(self, mock_read):
        assert inventory._read_sysfs_speed('eth0') == '25Gbit/s'

    @mock.patch('inventory._read_file', return_value='1000\n')
    def test_1g(self, mock_read):
        assert inventory._read_sysfs_speed('eth0') == '1Gbit/s'

    @mock.patch('inventory._read_file', return_value='100\n')
    def test_100m(self, mock_read):
        assert inventory._read_sysfs_speed('eth0') == '100Mbit/s'

    @mock.patch('inventory._read_file', return_value='-1\n')
    def test_negative(self, mock_read):
        assert inventory._read_sysfs_speed('eth0') is None

    @mock.patch('inventory._read_file', return_value='')
    def test_empty(self, mock_read):
        assert inventory._read_sysfs_speed('eth0') is None


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
