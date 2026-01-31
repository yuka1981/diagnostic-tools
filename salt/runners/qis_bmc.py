"""
QIS BMC Out-of-Band Management Runner

Runs on the Salt master to collect sensor data and hardware inventory
from BMCs via Redfish and IPMI protocols.

Usage:
    salt-run qis_bmc.collect_sensors
    salt-run qis_bmc.collect_sensors node=compute-001
    salt-run qis_bmc.collect_inventory node=compute-001
    salt-run qis_bmc.check_connectivity
"""

import json
import logging
import re
import subprocess
import time

try:
    import requests
except ImportError:
    requests = None

log = logging.getLogger(__name__)

# Protocol cache: {bmc_address: "redfish"|"ipmi"}
_protocol_cache = {}

# Salt dunder dicts — populated by Salt at runtime
__salt__ = {}
__opts__ = {}


def collect_sensors(node=None):
    """
    Collect sensor readings from BMCs.

    Args:
        node: Optional hostname to collect from a single node.
              If None, collects from all configured nodes.

    Returns:
        dict: Summary of collection results.
    """
    credentials = _fetch_credentials()
    if not credentials:
        return {"success": False, "error": "No BMC credentials configured"}

    if node:
        credentials = [c for c in credentials if c.get("hostname") == node]

    results = []
    errors = []

    for cred in credentials:
        try:
            protocol = _resolve_protocol(cred)
            if not protocol:
                errors.append({"node": cred["hostname"], "error": "Unreachable"})
                continue

            if protocol == "redfish":
                readings = _collect_sensors_redfish(cred)
            else:
                readings = _collect_sensors_ipmi(cred)

            result = {
                "node_hostname": cred["hostname"],
                "node_id": cred["node_id"],
                "protocol": protocol,
                "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "readings": readings,
            }
            results.append(result)
        except Exception as exc:
            log.error("Failed to collect sensors for %s: %s", cred["hostname"], exc)
            errors.append({"node": cred["hostname"], "error": str(exc)})

    # Fire event with results
    if results:
        __salt__["event.send"](
            tag="qis/bmc/sensors",
            data={"results": results, "errors": errors},
        )

    return {
        "success": True,
        "collected": len(results),
        "failed": len(errors),
        "errors": errors,
    }


def collect_inventory(node=None):
    """
    Collect hardware inventory from BMCs.

    Args:
        node: Optional hostname to collect from a single node.

    Returns:
        dict: Summary of collection results.
    """
    credentials = _fetch_credentials()
    if not credentials:
        return {"success": False, "error": "No BMC credentials configured"}

    if node:
        credentials = [c for c in credentials if c.get("hostname") == node]

    results = []
    errors = []

    for cred in credentials:
        try:
            protocol = _resolve_protocol(cred)
            if not protocol:
                errors.append({"node": cred["hostname"], "error": "Unreachable"})
                continue

            if protocol == "redfish":
                inventory = _collect_inventory_redfish(cred)
            else:
                inventory = _collect_inventory_ipmi(cred)

            result = {
                "node_hostname": cred["hostname"],
                "node_id": cred["node_id"],
                "protocol": protocol,
                "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "inventory": inventory,
            }
            results.append(result)
        except Exception as exc:
            log.error("Failed to collect inventory for %s: %s", cred["hostname"], exc)
            errors.append({"node": cred["hostname"], "error": str(exc)})

    if results:
        __salt__["event.send"](
            tag="qis/bmc/inventory",
            data={"results": results, "errors": errors},
        )

    return {
        "success": True,
        "collected": len(results),
        "failed": len(errors),
        "errors": errors,
    }


def check_connectivity(node=None):
    """
    Check BMC connectivity for configured nodes.

    Returns:
        dict: Per-node connectivity status.
    """
    credentials = _fetch_credentials()
    if not credentials:
        return {"success": False, "error": "No BMC credentials configured"}

    if node:
        credentials = [c for c in credentials if c.get("hostname") == node]

    statuses = []
    for cred in credentials:
        protocol = _detect_protocol(
            cred["bmc_address"], cred["username"], cred["password"],
            cred.get("verify_ssl", True)
        )
        statuses.append({
            "node": cred["hostname"],
            "node_id": cred["node_id"],
            "bmc_address": cred["bmc_address"],
            "reachable": protocol is not None,
            "protocol": protocol,
        })

    return {"success": True, "statuses": statuses}


# --- Internal helpers ---


def _fetch_credentials():
    """Fetch BMC credentials from Rails API."""
    rails_url = __opts__.get("qis_rails_url", "http://localhost:3000")
    api_token = __opts__.get("qis_api_token", "")

    try:
        resp = requests.get(
            f"{rails_url}/api/v1/bmc/credentials",
            headers={"Authorization": f"Bearer {api_token}"},
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json().get("credentials", [])
    except Exception as exc:
        log.error("Failed to fetch BMC credentials from Rails: %s", exc)
        return []


def _resolve_protocol(cred):
    """Resolve protocol for a node, using cache and explicit setting."""
    bmc_addr = cred["bmc_address"]
    explicit = cred.get("protocol", "auto")

    if explicit in ("redfish", "ipmi"):
        return explicit

    if bmc_addr in _protocol_cache:
        return _protocol_cache[bmc_addr]

    detected = _detect_protocol(
        bmc_addr, cred["username"], cred["password"],
        cred.get("verify_ssl", True)
    )
    if detected:
        _protocol_cache[bmc_addr] = detected
    return detected


def _detect_protocol(address, username, password, verify_ssl):
    """Auto-detect: try Redfish first, then IPMI."""
    # Try Redfish
    if requests:
        try:
            resp = requests.get(
                f"https://{address}/redfish/v1/",
                auth=(username, password),
                verify=verify_ssl,
                timeout=5,
            )
            if resp.status_code == 200:
                return "redfish"
        except Exception:
            pass

    # Try IPMI
    try:
        result = subprocess.run(
            ["ipmitool", "-H", address, "-U", username, "-P", password, "mc", "info"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            return "ipmi"
    except Exception:
        pass

    return None


def _collect_sensors_redfish(cred):
    """Collect sensor readings via Redfish API."""
    base = f"https://{cred['bmc_address']}"
    auth = (cred["username"], cred["password"])
    verify = cred.get("verify_ssl", True)
    readings = []

    # Thermal sensors
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Chassis/1/Thermal",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            for temp in data.get("Temperatures", []):
                if temp.get("ReadingCelsius") is not None:
                    readings.append({
                        "type": "temperature",
                        "name": temp.get("Name", "unknown").lower().replace(" ", "_"),
                        "value": float(temp["ReadingCelsius"]),
                        "unit": "celsius",
                        "status": _redfish_health(temp.get("Status", {})),
                    })
            for fan in data.get("Fans", []):
                if fan.get("Reading") is not None:
                    unit = "percent" if fan.get("ReadingUnits") == "Percent" else "rpm"
                    readings.append({
                        "type": "fan",
                        "name": fan.get("Name", "unknown").lower().replace(" ", "_"),
                        "value": float(fan["Reading"]),
                        "unit": unit,
                        "status": _redfish_health(fan.get("Status", {})),
                    })
    except Exception as exc:
        log.warning("Redfish Thermal query failed: %s", exc)

    # Power sensors
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Chassis/1/Power",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            for psu in data.get("PowerControl", []):
                if psu.get("PowerConsumedWatts") is not None:
                    readings.append({
                        "type": "power",
                        "name": psu.get("Name", "total").lower().replace(" ", "_"),
                        "value": float(psu["PowerConsumedWatts"]),
                        "unit": "watts",
                        "status": _redfish_health(psu.get("Status", {})),
                    })
    except Exception as exc:
        log.warning("Redfish Power query failed: %s", exc)

    return readings


def _collect_sensors_ipmi(cred):
    """Collect sensor readings via ipmitool sdr."""
    result = subprocess.run(
        [
            "ipmitool", "-H", cred["bmc_address"],
            "-U", cred["username"], "-P", cred["password"],
            "sdr", "type", "Temperature", "Fan", "Current",
        ],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(f"ipmitool sdr failed: {result.stderr}")

    return _parse_ipmi_sdr(result.stdout)


def _parse_ipmi_sdr(output):
    """Parse ipmitool sdr output into structured readings."""
    readings = []
    for line in output.strip().split("\n"):
        if not line.strip():
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 3:
            continue

        name = parts[0].lower().replace(" ", "_")
        value_str = parts[1]
        status = "ok" if "ok" in parts[2].lower() else "warning"

        # Parse value and unit
        match = re.match(
            r"([\d.]+)\s*(degrees C|RPM|Watts|Percent)",
            value_str, re.IGNORECASE,
        )
        if not match:
            continue

        value = float(match.group(1))
        raw_unit = match.group(2).lower()

        if "degrees" in raw_unit:
            sensor_type, unit = "temperature", "celsius"
        elif "rpm" in raw_unit:
            sensor_type, unit = "fan", "rpm"
        elif "watts" in raw_unit:
            sensor_type, unit = "power", "watts"
        elif "percent" in raw_unit:
            sensor_type, unit = "fan", "percent"
        else:
            continue

        readings.append({
            "type": sensor_type,
            "name": name,
            "value": value,
            "unit": unit,
            "status": status,
        })

    return readings


def _collect_inventory_redfish(cred):
    """Collect hardware inventory via Redfish API."""
    base = f"https://{cred['bmc_address']}"
    auth = (cred["username"], cred["password"])
    verify = cred.get("verify_ssl", True)
    inventory = {
        "processors": [], "memory": [], "storage": [],
        "network": [], "infiniband": [],
        "bios": {}, "bmc_info": {},
    }

    # Processors
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Systems/1/Processors",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            for member in resp.json().get("Members", []):
                proc_resp = requests.get(
                    f"{base}{member['@odata.id']}",
                    auth=auth, verify=verify, timeout=10,
                )
                if proc_resp.status_code == 200:
                    p = proc_resp.json()
                    inventory["processors"].append({
                        "socket": p.get("Socket", ""),
                        "model": p.get("Model", ""),
                        "cores_physical": p.get("TotalCores", 0),
                        "freq_base": p.get("MaxSpeedMHz", 0),
                        "freq_max": p.get("MaxSpeedMHz", 0),
                        "serial": p.get("SerialNumber", ""),
                        "architecture": p.get("InstructionSet", ""),
                    })
    except Exception as exc:
        log.warning("Redfish Processors query failed: %s", exc)

    # Memory
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Systems/1/Memory",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            for member in resp.json().get("Members", []):
                mem_resp = requests.get(
                    f"{base}{member['@odata.id']}",
                    auth=auth, verify=verify, timeout=10,
                )
                if mem_resp.status_code == 200:
                    m = mem_resp.json()
                    inventory["memory"].append({
                        "slot": m.get("DeviceLocator", ""),
                        "size_gb": m.get("CapacityMiB", 0) / 1024,
                        "speed_mhz": m.get("OperatingSpeedMhz", 0),
                        "manufacturer": m.get("Manufacturer", ""),
                        "serial": m.get("SerialNumber", ""),
                        "type": m.get("MemoryDeviceType", ""),
                    })
    except Exception as exc:
        log.warning("Redfish Memory query failed: %s", exc)

    # BIOS
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Systems/1/Bios",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            b = resp.json()
            inventory["bios"] = {
                "vendor": b.get("Attributes", {}).get("SystemManufacturer", ""),
                "version": b.get("BiosVersion", b.get("Id", "")),
                "release_date": b.get("Attributes", {}).get(
                    "SystemBiosReleaseDate", ""
                ),
            }
    except Exception as exc:
        log.warning("Redfish BIOS query failed: %s", exc)

    # BMC Info
    try:
        resp = requests.get(
            f"{base}/redfish/v1/Managers/1",
            auth=auth, verify=verify, timeout=10,
        )
        if resp.status_code == 200:
            mgr = resp.json()
            inventory["bmc_info"] = {
                "model": mgr.get("Model", ""),
                "firmware": mgr.get("FirmwareVersion", ""),
                "ip": cred["bmc_address"],
            }
    except Exception as exc:
        log.warning("Redfish Manager query failed: %s", exc)

    return inventory


def _collect_inventory_ipmi(cred):
    """Collect hardware inventory via ipmitool."""
    inventory = {
        "processors": [], "memory": [], "storage": [],
        "network": [], "infiniband": [],
        "bios": {}, "bmc_info": {},
    }
    base_cmd = [
        "ipmitool", "-H", cred["bmc_address"],
        "-U", cred["username"], "-P", cred["password"],
    ]

    # FRU data
    try:
        result = subprocess.run(
            base_cmd + ["fru", "print"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            fru = _parse_ipmi_fru(result.stdout)
            inventory["bios"] = {
                "vendor": fru.get("Board Mfg", ""),
                "version": fru.get("Product Version", ""),
                "release_date": fru.get("Board Mfg Date", ""),
            }
    except Exception as exc:
        log.warning("ipmitool fru failed: %s", exc)

    # BMC info
    try:
        result = subprocess.run(
            base_cmd + ["mc", "info"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            mc = _parse_ipmi_mc_info(result.stdout)
            inventory["bmc_info"] = {
                "model": mc.get("Device ID", ""),
                "firmware": mc.get("Firmware Revision", ""),
                "ip": cred["bmc_address"],
            }
    except Exception as exc:
        log.warning("ipmitool mc info failed: %s", exc)

    return inventory


def _parse_ipmi_fru(output):
    """Parse ipmitool fru print output into a dict."""
    result = {}
    for line in output.split("\n"):
        if ":" in line:
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip()
    return result


def _parse_ipmi_mc_info(output):
    """Parse ipmitool mc info output into a dict."""
    result = {}
    for line in output.split("\n"):
        if ":" in line:
            key, _, value = line.partition(":")
            result[key.strip()] = value.strip()
    return result


def _redfish_health(status_obj):
    """Convert Redfish Status to simple status string."""
    health = status_obj.get("Health", "OK")
    return {"OK": "ok", "Warning": "warning", "Critical": "critical"}.get(
        health, "ok"
    )
