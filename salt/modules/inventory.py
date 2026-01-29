"""
Salt custom execution module for system inventory collection.
Collects DMI, NUMA topology, and advanced network device information.

Usage via salt-api:
    salt 'minion-id' inventory.collect_dmi
    salt 'minion-id' inventory.collect_numa
    salt 'minion-id' inventory.collect_network_v2
"""

import json
import os
import re
import subprocess


__virtualname__ = 'inventory'


def __virtual__():
    return __virtualname__


# --- DMI Collection ---

def collect_dmi():
    """Collect DMI information from the system using dmidecode."""
    try:
        return {
            'bios': _parse_dmi_section(_run_dmidecode('bios')),
            'system': _parse_dmi_section(_run_dmidecode('system')),
            'baseboard': _parse_dmi_section(_run_dmidecode('baseboard')),
        }
    except FileNotFoundError as e:
        return {'error': str(e)}
    except subprocess.CalledProcessError as e:
        return {'error': f'dmidecode failed: {e.returncode}'}


def _run_dmidecode(dmi_type):
    """Run dmidecode for a specific type."""
    type_map = {'bios': '0', 'system': '1', 'baseboard': '2'}
    result = subprocess.run(
        ['dmidecode', '-t', type_map[dmi_type]],
        capture_output=True, text=True, timeout=10
    )
    return result.stdout


def _parse_dmi_section(output):
    """Parse dmidecode output into a dict of key-value pairs."""
    data = {}
    for line in output.splitlines():
        line = line.strip()
        if ':' in line and not line.endswith(':'):
            key, _, value = line.partition(':')
            key = key.strip().lower().replace(' ', '_')
            value = value.strip()
            if value:
                data[key] = value
    return data


# --- NUMA Topology ---

def collect_numa():
    """Collect NUMA topology from /sys/devices/system/node/."""
    numa_nodes = _list_numa_nodes()
    nodes = {}

    for node_dir in numa_nodes:
        node_num = node_dir.replace('node', '')
        base_path = f'/sys/devices/system/node/{node_dir}'
        cpulist = _read_file(f'{base_path}/cpulist').strip()
        meminfo = _read_file(f'{base_path}/meminfo')
        memory_kb = _parse_memtotal(meminfo)
        nodes[node_num] = {'cpulist': cpulist, 'memory_kb': memory_kb}

    return {'node_count': len(numa_nodes), 'nodes': nodes}


def _list_numa_nodes():
    base = '/sys/devices/system/node'
    if not os.path.isdir(base):
        return []
    return sorted([d for d in os.listdir(base) if d.startswith('node') and d[4:].isdigit()])


def _read_file(path):
    try:
        with open(path, 'r') as f:
            return f.read()
    except (IOError, OSError):
        return ''


def _parse_memtotal(meminfo):
    match = re.search(r'MemTotal:\s+(\d+)\s+kB', meminfo)
    return int(match.group(1)) if match else 0


# --- Network V2 (lshw) ---

def collect_network_v2():
    """Collect advanced network device information using lshw."""
    try:
        raw = _run_lshw()
        entries = json.loads(raw)
        devices = []
        for entry in entries:
            config = entry.get('configuration', {})
            devices.append({
                'name': entry.get('logicalname', ''),
                'product': entry.get('product', ''),
                'vendor': entry.get('vendor', ''),
                'mac': entry.get('serial', ''),
                'driver': config.get('driver', ''),
                'speed': config.get('speed', ''),
                'link': config.get('link', ''),
                'pci_slot': entry.get('handle', ''),
            })
        return {'devices': devices}
    except FileNotFoundError as e:
        return {'error': str(e)}
    except (json.JSONDecodeError, subprocess.CalledProcessError) as e:
        return {'error': f'lshw failed: {e}'}


def _run_lshw():
    result = subprocess.run(
        ['lshw', '-class', 'network', '-json'],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout
