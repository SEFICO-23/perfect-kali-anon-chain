# Windows Network Hardening

Strip unnecessary protocols from your Windows network adapters.
Less surface area = fewer ways for traffic to leak outside the VPN.

---

## What We're Removing

Each network adapter in Windows has "bindings" — protocols and services
attached to it. Most of them you don't need and they create attack/leak surface:

| Binding | What it is | Why remove |
|---------|-----------|-----------|
| `ms_msclient` | Windows file sharing (SMB client) | Not needed for internet |
| `ms_server` | Windows file sharing (SMB server) | Not needed, potential pivot |
| `ms_lldp` | Link-Layer Discovery Protocol | Network enumeration |
| `ms_lltdio` | Link Layer Topology Discovery | Network mapping |
| `ms_rspndr` | Topology Discovery Responder | Responds to mapping queries |
| `ms_tcpip6` | IPv6 | Force IPv4-only; IPv6 leaks are common |
| `ms_l2bridge` | Layer 2 Bridge | Not needed |

---

## The Script

Run `scripts/windows/harden-adapters.ps1` as Administrator.

It targets these adapters (edit the script to match yours):
- `Wi-Fi` — your main internet adapter (replace with your actual adapter name)
- `Mullvad` — Mullvad's virtual adapter
- `vEthernet (WSL)` — the WSL2 bridge

**Before running, find your adapter names:**

```powershell
Get-NetAdapter | Select-Object Name, Status, InterfaceDescription
```

Edit the `$adapters` array in the script to match your adapter names.

**Run the script:**

```powershell
# From an Administrator PowerShell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\harden-adapters.ps1
```

---

## What the Script Does

```powershell
# For each adapter:
Disable-NetAdapterBinding -Name $adapter -ComponentID ms_msclient   # No SMB client
Disable-NetAdapterBinding -Name $adapter -ComponentID ms_server     # No SMB server
Disable-NetAdapterBinding -Name $adapter -ComponentID ms_lldp       # No LLDP
Disable-NetAdapterBinding -Name $adapter -ComponentID ms_lltdio     # No topology discovery
Disable-NetAdapterBinding -Name $adapter -ComponentID ms_rspndr     # No topology response
Disable-NetAdapterBinding -Name $adapter -ComponentID ms_tcpip6     # No IPv6
Disable-NetAdapterBinding -Name $adapter -ComponentID ms_l2bridge   # No L2 bridge
```

> **Why PowerShell + UAC instead of GUI?**
> You can do this manually via `ncpa.cpl` → adapter properties → uncheck bindings.
> The script automates it, is repeatable, and documents exactly what was changed.

---

## VirtualBox (Remove If Installed)

VirtualBox installs a kernel driver and virtual adapter (`Ethernet 2` /
`VirtualBox Host-Only Adapter`). These add unnecessary network interfaces
and a kernel-level driver with a large attack surface.

If installed, uninstall it fully:

```
Control Panel → Programs → Uninstall VirtualBox
```

After uninstall, verify the `Ethernet 2` adapter is gone:

```powershell
Get-NetAdapter | Select-Object Name, Status
```

---

## Mullvad App Settings (Windows)

These settings harden the Windows Mullvad client:

| Setting | Value | Reason |
|---------|-------|--------|
| Multihop | Entry → Exit (your choice) | Two Mullvad servers in chain |
| DAITA | ON | Traffic pattern obfuscation (Windows only — see [Doc 05](05-mullvad-kali.md) for why this is incompatible with the Kali Tor chain) |
| Quantum Resistance | ON | Post-quantum WireGuard keys |
| Lockdown Mode | ON | Block all internet if VPN drops |
| DNS | Mullvad internal (10.64.0.1) | Prevent DNS leaks |

> **Lockdown Mode** is a kill-switch at the Windows level. If Mullvad
> disconnects for any reason, ALL internet traffic is blocked — no fallback
> to clearnet. This ensures you're never accidentally exposed.

---

## Verify

After hardening, check no IPv6 is leaking:

```powershell
Test-NetConnection -ComputerName ipv6.google.com -Port 80
# Should fail or timeout
```

Check Mullvad's leak test at [mullvad.net/check](https://mullvad.net/check)
from Windows browser — should show only the Mullvad exit IP.
