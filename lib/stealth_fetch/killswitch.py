"""KillSwitch — Network leak prevention.

Verifies the VPN-over-Tor chain is active before allowing any request.
Prevents IP leaks if Mullvad disconnects mid-session.

Checks:
1. Mullvad status is "Connected"
2. The wg0-mullvad interface exists (interface binding target)
3. DNS resolv.conf points to safe resolvers (Mullvad or Quad9)
"""

import subprocess
import os
from pathlib import Path


class NetworkLeakError(Exception):
    """Raised when the network is not safe for anonymous requests."""
    pass


# Known safe DNS resolvers
SAFE_DNS = {
    "10.64.0.1",       # Mullvad internal DNS
    "9.9.9.9",         # Quad9 primary
    "149.112.112.112",  # Quad9 secondary
}


def verify(skip: bool = False) -> dict:
    """Verify the anonymization chain is active.

    Args:
        skip: If True, skip all checks (unsafe, for testing only).

    Returns:
        dict with verification results:
        - mullvad_connected: bool
        - interface_exists: bool
        - dns_safe: bool
        - mullvad_interface: str (interface name if found)

    Raises:
        NetworkLeakError: If any check fails and skip=False.
    """
    result = {
        "mullvad_connected": False,
        "interface_exists": False,
        "dns_safe": False,
        "mullvad_interface": "",
    }

    if skip:
        return result

    # ── Check 1: Mullvad status ──────────────────────────────────────────
    try:
        status = subprocess.run(
            ["mullvad", "status"],
            capture_output=True, text=True, timeout=5,
        )
        if "Connected" in status.stdout:
            result["mullvad_connected"] = True
        else:
            raise NetworkLeakError(
                f"Mullvad is not connected: {status.stdout.strip()}\n"
                "Run: sudo mullvad connect"
            )
    except FileNotFoundError:
        raise NetworkLeakError(
            "Mullvad CLI not found. Is mullvad-vpn installed?"
        )
    except subprocess.TimeoutExpired:
        raise NetworkLeakError("Mullvad status check timed out")

    # ── Check 2: WireGuard interface exists ──────────────────────────────
    # Look for wg0-mullvad or similar Mullvad interface
    mullvad_iface = ""
    try:
        ip_output = subprocess.run(
            ["ip", "link", "show"],
            capture_output=True, text=True, timeout=5,
        )
        for line in ip_output.stdout.splitlines():
            for iface_name in ("wg0-mullvad", "wg-mullvad", "wg0"):
                if iface_name in line:
                    mullvad_iface = iface_name
                    break
            if mullvad_iface:
                break
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    if mullvad_iface:
        result["interface_exists"] = True
        result["mullvad_interface"] = mullvad_iface
    else:
        raise NetworkLeakError(
            "Mullvad WireGuard interface not found (wg0-mullvad).\n"
            "Mullvad may be connecting or using a different tunnel type."
        )

    # ── Check 3: DNS resolver safety ─────────────────────────────────────
    resolv_path = Path("/etc/resolv.conf")
    if resolv_path.exists():
        content = resolv_path.read_text()
        nameservers = []
        for line in content.splitlines():
            line = line.strip()
            if line.startswith("nameserver"):
                ns = line.split()[1] if len(line.split()) > 1 else ""
                nameservers.append(ns)

        if nameservers:
            unsafe = [ns for ns in nameservers if ns not in SAFE_DNS]
            if not unsafe:
                result["dns_safe"] = True
            else:
                raise NetworkLeakError(
                    f"Unsafe DNS resolver detected: {', '.join(unsafe)}\n"
                    f"Expected one of: {', '.join(sorted(SAFE_DNS))}\n"
                    "Fix: sudo systemctl restart kali-dns"
                )
        else:
            raise NetworkLeakError(
                "No nameservers in /etc/resolv.conf\n"
                "Fix: sudo systemctl restart kali-dns"
            )
    else:
        raise NetworkLeakError(
            "/etc/resolv.conf does not exist\n"
            "Fix: sudo systemctl restart kali-dns"
        )

    return result
