"""
Salt custom execution module for system inventory collection.
Collects DMI, NUMA topology, CPU topology, and advanced network device information.

Usage via salt-api:
    salt 'minion-id' inventory.collect_dmi
    salt 'minion-id' inventory.collect_numa
    salt 'minion-id' inventory.collect_cpu
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
            'memory': _parse_dmi_memory(_run_dmidecode('memory')),
        }
    except FileNotFoundError as e:
        return {'error': str(e)}
    except subprocess.CalledProcessError as e:
        return {'error': f'dmidecode failed: {e.returncode}'}
    except subprocess.TimeoutExpired as e:
        return {'error': f'dmidecode timed out after {e.timeout}s'}


def _run_dmidecode(dmi_type):
    """Run dmidecode for a specific type."""
    type_map = {'bios': '0', 'system': '1', 'baseboard': '2', 'memory': '17'}
    result = subprocess.run(
        ['dmidecode', '-t', type_map[dmi_type]],
        capture_output=True, text=True, timeout=10, check=True
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


def _parse_dmi_memory(output):
    """Parse dmidecode -t 17 output into a list of memory device dicts."""
    devices = []
    current = None
    for line in output.splitlines():
        stripped = line.strip()
        if stripped == 'Memory Device':
            if current is not None:
                devices.append(current)
            current = {}
            continue
        if current is None:
            continue
        if ':' in stripped and not stripped.endswith(':'):
            key, _, value = stripped.partition(':')
            key = key.strip().lower().replace(' ', '_')
            value = value.strip()
            if value:
                current[key] = value
    if current is not None:
        devices.append(current)
    return devices


# --- Memory Info ---

def collect_meminfo():
    """Collect memory info from /proc/meminfo."""
    try:
        raw = _read_file('/proc/meminfo')
        return _parse_proc_meminfo(raw)
    except Exception as e:
        return {'error': str(e)}


def _parse_proc_meminfo(raw):
    """Parse /proc/meminfo into a dict of values in kB."""
    data = {}
    for line in raw.splitlines():
        if ':' not in line:
            continue
        key, _, value = line.partition(':')
        key = key.strip()
        value = value.strip()
        # Strip ' kB' suffix and convert to int
        match = re.match(r'^(\d+)\s*kB$', value)
        if match:
            data[key] = int(match.group(1))
        elif value.isdigit():
            data[key] = int(value)
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


# --- CPU Topology ---

def collect_cpu():
    """Collect CPU topology from /proc/cpuinfo."""
    try:
        cpuinfo = _read_file('/proc/cpuinfo')
        return _parse_cpuinfo(cpuinfo)
    except Exception as e:
        return {'error': str(e)}


def _parse_cpuinfo(cpuinfo):
    """Parse /proc/cpuinfo to extract CPU topology."""
    physical_ids = set()
    core_ids_per_socket = {}
    processor_count = 0
    model_name = ''
    flags = []

    current_physical_id = None

    for line in cpuinfo.splitlines():
        line = line.strip()
        if not line:
            current_physical_id = None
            continue

        if ':' not in line:
            continue

        key, _, value = line.partition(':')
        key = key.strip()
        value = value.strip()

        if key == 'processor':
            processor_count += 1
        elif key == 'physical id':
            current_physical_id = value
            physical_ids.add(value)
        elif key == 'core id' and current_physical_id is not None:
            core_ids_per_socket.setdefault(current_physical_id, set()).add(value)
        elif key == 'model name' and not model_name:
            model_name = value
        elif key == 'flags' and not flags:
            flags = value.split()

    sockets = len(physical_ids) if physical_ids else 1
    total_cores = sum(len(cores) for cores in core_ids_per_socket.values()) if core_ids_per_socket else processor_count
    cores_per_socket = total_cores // sockets if sockets > 0 else total_cores
    threads_per_core = processor_count // total_cores if total_cores > 0 else 1

    return {
        'model_name': model_name,
        'sockets': sockets,
        'cores': total_cores,
        'cores_per_socket': cores_per_socket,
        'threads': processor_count,
        'threads_per_core': threads_per_core,
        'flags': flags,
    }


# --- Network V2 (lshw + sysfs) ---

def collect_network_v2():
    """Collect advanced network device information using lshw and sysfs.

    Combines hardware info from lshw with runtime state from sysfs and the
    ``ip`` command.  Interfaces that lshw does not report (bridges, bonds,
    VLANs, etc.) are discovered via /sys/class/net/.  Loopback (``lo``) is
    always excluded.
    """
    try:
        lshw_devices = _collect_lshw_devices()
    except FileNotFoundError as e:
        return {'error': str(e)}
    except (json.JSONDecodeError, subprocess.CalledProcessError) as e:
        return {'error': f'lshw failed: {e}'}
    except subprocess.TimeoutExpired as e:
        return {'error': f'lshw timed out after {e.timeout}s'}

    # Index lshw devices by logical name for enrichment
    devices_by_name = {d['name']: d for d in lshw_devices if d.get('name')}

    # Discover all interfaces from sysfs and merge
    sysfs_ifaces = _list_sysfs_interfaces()
    for iface_name in sysfs_ifaces:
        if iface_name == 'lo':
            continue
        if iface_name in devices_by_name:
            # Enrich existing lshw device with sysfs / ip data
            _enrich_device(devices_by_name[iface_name])
        else:
            # Create a new device entry from sysfs / ip data only
            dev = _build_sysfs_device(iface_name)
            devices_by_name[iface_name] = dev

    # Also enrich any lshw device whose name was not found in sysfs
    # (unlikely, but keeps data consistent)
    for dev in devices_by_name.values():
        if 'oper_state' not in dev:
            _enrich_device(dev)

    # Return devices sorted by name for deterministic output
    devices = sorted(devices_by_name.values(), key=lambda d: d.get('name', ''))
    return {'devices': devices}


def _collect_lshw_devices():
    """Run lshw and return a list of device dicts with view-compatible keys."""
    raw = _run_lshw()
    entries = json.loads(raw)
    devices = []
    for entry in entries:
        config = entry.get('configuration', {})
        pci_handle = entry.get('handle', '')
        # Normalise PCI handle from lshw (e.g. "PCI:0000:3b:00.0" -> "0000:3b:00.0")
        pci_address = pci_handle.replace('PCI:', '') if pci_handle else ''
        devices.append({
            'name': entry.get('logicalname', ''),
            'model': entry.get('product', ''),
            'vendor': entry.get('vendor', ''),
            'mac': entry.get('serial', ''),
            'driver': config.get('driver', ''),
            'speed': config.get('speed', ''),
            'link': config.get('link', ''),
            'pci_address': pci_address,
        })
    return devices


def _enrich_device(dev):
    """Add sysfs / ip runtime fields to an existing device dict."""
    name = dev.get('name', '')
    if not name:
        return
    dev['oper_state'] = _read_sysfs_attr(name, 'operstate')
    dev['type'] = _detect_interface_type(name)
    dev['ip_addresses'] = _get_ip_addresses(name)
    dev['master'] = _get_master(name)


def _build_sysfs_device(name):
    """Create a device dict for an interface discovered only via sysfs."""
    return {
        'name': name,
        'model': None,
        'vendor': None,
        'mac': _read_sysfs_attr(name, 'address'),
        'driver': _get_driver_name(name),
        'speed': _read_sysfs_speed(name),
        'link': None,
        'pci_address': _get_pci_address_from_sysfs(name),
        'oper_state': _read_sysfs_attr(name, 'operstate'),
        'type': _detect_interface_type(name),
        'ip_addresses': _get_ip_addresses(name),
        'master': _get_master(name),
    }


# --- sysfs helpers ---

def _list_sysfs_interfaces():
    """Return a sorted list of interface names from /sys/class/net/."""
    base = '/sys/class/net'
    try:
        return sorted(os.listdir(base))
    except OSError:
        return []


def _read_sysfs_attr(iface, attr):
    """Read a single sysfs attribute for an interface, returning None on failure."""
    value = _read_file(f'/sys/class/net/{iface}/{attr}').strip()
    return value if value else None


def _detect_interface_type(iface):
    """Determine the type of a network interface from sysfs.

    Checks the ARPHRD type code first, then looks for well-known virtual
    interface indicators in sysfs.
    """
    type_code = _read_file(f'/sys/class/net/{iface}/type').strip()

    # ARPHRD_INFINIBAND = 32
    if type_code == '32':
        return 'infiniband'

    # Check for virtual interface types via sysfs directory presence
    base = f'/sys/class/net/{iface}'
    if os.path.isdir(f'{base}/bridge'):
        return 'bridge'
    if os.path.isdir(f'{base}/bonding'):
        return 'bond'
    # VLAN interfaces have a parent link in /proc/net/vlan/
    if os.path.isfile(f'/proc/net/vlan/{iface}'):
        return 'vlan'

    # ARPHRD_ETHER = 1
    if type_code == '1':
        return 'ethernet'

    return 'other'


def _get_master(iface):
    """Return the master interface name, or None."""
    master_path = f'/sys/class/net/{iface}/master'
    try:
        target = os.readlink(master_path)
        return os.path.basename(target)
    except OSError:
        return None


def _get_driver_name(iface):
    """Resolve the kernel driver for an interface from its sysfs device/driver symlink."""
    driver_link = f'/sys/class/net/{iface}/device/driver'
    try:
        target = os.readlink(driver_link)
        return os.path.basename(target)
    except OSError:
        return None


def _get_pci_address_from_sysfs(iface):
    """Resolve PCI address by reading the device symlink in sysfs."""
    device_link = f'/sys/class/net/{iface}/device'
    try:
        target = os.readlink(device_link)
        return os.path.basename(target)
    except OSError:
        return None


def _read_sysfs_speed(iface):
    """Read interface speed from sysfs, returning None on failure.

    The kernel reports speed in Mbit/s as a plain integer.  We convert to a
    human-friendly string like ``1Gbit/s`` or ``25Gbit/s``.
    """
    raw = _read_file(f'/sys/class/net/{iface}/speed').strip()
    if not raw:
        return None
    try:
        mbit = int(raw)
    except ValueError:
        return None
    if mbit <= 0:
        return None
    if mbit >= 1000 and mbit % 1000 == 0:
        return f'{mbit // 1000}Gbit/s'
    return f'{mbit}Mbit/s'


# --- ip command helpers ---

def _get_ip_addresses(iface):
    """Return a list of IP addresses (with prefix length) for *iface*.

    Tries ``ip -j addr show <iface>`` first (JSON output).  Falls back to
    parsing text output of ``ip addr show <iface>`` and /proc/net/if_inet6.
    """
    addrs = _get_ip_addresses_json(iface)
    if addrs is not None:
        return addrs
    return _get_ip_addresses_fallback(iface)


def _get_ip_addresses_json(iface):
    """Try to get addresses via ``ip -j addr show``."""
    try:
        result = subprocess.run(
            ['ip', '-j', 'addr', 'show', iface],
            capture_output=True, text=True, timeout=5, check=True,
        )
        data = json.loads(result.stdout)
        addrs = []
        for entry in data:
            for addr_info in entry.get('addr_info', []):
                local = addr_info.get('local', '')
                prefixlen = addr_info.get('prefixlen', '')
                if local:
                    addrs.append(f'{local}/{prefixlen}' if prefixlen else local)
        return addrs
    except (FileNotFoundError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError, KeyError):
        return None


def _get_ip_addresses_fallback(iface):
    """Fallback: parse ``ip addr show`` text + /proc/net/if_inet6."""
    addrs = []
    # IPv4 from ip addr show
    try:
        result = subprocess.run(
            ['ip', 'addr', 'show', iface],
            capture_output=True, text=True, timeout=5, check=True,
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.startswith('inet '):
                parts = line.split()
                if len(parts) >= 2:
                    addrs.append(parts[1])  # e.g. "192.168.1.10/24"
            elif line.startswith('inet6 '):
                parts = line.split()
                if len(parts) >= 2:
                    addrs.append(parts[1])
    except (FileNotFoundError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired):
        pass

    # If we got nothing for IPv6, try /proc/net/if_inet6
    if not any(':' in a for a in addrs):
        addrs.extend(_parse_proc_if_inet6(iface))

    return addrs


def _parse_proc_if_inet6(iface):
    """Parse /proc/net/if_inet6 for addresses belonging to *iface*."""
    addrs = []
    raw = _read_file('/proc/net/if_inet6')
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) >= 6 and parts[5] == iface:
            hex_addr = parts[0]
            prefix_len = int(parts[2], 16)
            # Expand compressed IPv6 from the hex string
            groups = [hex_addr[i:i + 4] for i in range(0, 32, 4)]
            ipv6 = ':'.join(groups)
            addrs.append(f'{ipv6}/{prefix_len}')
    return addrs


def _run_lshw():
    result = subprocess.run(
        ['lshw', '-class', 'network', '-json'],
        capture_output=True, text=True, timeout=30, check=True
    )
    return result.stdout
