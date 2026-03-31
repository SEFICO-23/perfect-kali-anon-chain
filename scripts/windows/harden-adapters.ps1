# harden-adapters.ps1
#
# Strips unnecessary protocol bindings from Windows network adapters.
# Run as Administrator.
#
# WHAT THIS REMOVES:
#   ms_msclient   Windows SMB file sharing client (not needed for internet)
#   ms_server     Windows SMB file sharing server (attack surface)
#   ms_lldp       Link-Layer Discovery Protocol (network enumeration)
#   ms_lltdio     Link Layer Topology Discovery I/O (network mapping)
#   ms_rspndr     Topology Discovery Responder (responds to network scans)
#   ms_tcpip6     IPv6 (force IPv4-only; IPv6 leaks bypass VPN on many setups)
#   ms_l2bridge   Layer 2 Bridge (not needed)
#
# WHAT THIS KEEPS:
#   ms_tcpip      IPv4 (required)
#   ms_pacer      QoS Packet Scheduler (required for WSL)
#   ms_ndisuio    NDIS Usermode I/O (required for some VPN features)
#
# IMPORTANT: Edit $adapters to match your actual adapter names.
# Find them with: Get-NetAdapter | Select-Object Name, Status

param(
    [switch]$WhatIf   # Use -WhatIf to preview changes without applying
)

# ── Configuration ─────────────────────────────────────────────────────────────
# Edit these to match your adapter names
$adapters = @(
    "Wi-Fi",              # Your primary wireless adapter
    "Wi-Fi 3",            # If you have multiple Wi-Fi adapters
    "Mullvad",            # Mullvad VPN virtual adapter
    "vEthernet (WSL)"     # WSL2 virtual switch
)

# Protocol component IDs to disable
$removeBindings = @(
    "ms_msclient",   # Client for Microsoft Networks
    "ms_server",     # File and Printer Sharing
    "ms_lldp",       # Link-Layer Topology Discovery Mapper I/O Driver
    "ms_lltdio",     # Link-Layer Topology Discovery Mapper I/O
    "ms_rspndr",     # Link-Layer Topology Discovery Responder
    "ms_tcpip6",     # Internet Protocol Version 6 (TCP/IPv6)
    "ms_l2bridge"    # MAC Bridge Miniport
)
# ──────────────────────────────────────────────────────────────────────────────

$successCount = 0
$skipCount    = 0
$errorCount   = 0

Write-Host "`nKali Anon Chain — Windows Adapter Hardening" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

foreach ($adapter in $adapters) {
    # Check adapter exists
    $adapterObj = Get-NetAdapter -Name $adapter -ErrorAction SilentlyContinue
    if (-not $adapterObj) {
        Write-Host "`n[SKIP] Adapter not found: $adapter" -ForegroundColor Yellow
        $skipCount++
        continue
    }

    Write-Host "`n[$adapter] ($($adapterObj.InterfaceDescription))" -ForegroundColor White

    foreach ($binding in $removeBindings) {
        $current = Get-NetAdapterBinding -Name $adapter -ComponentID $binding -ErrorAction SilentlyContinue
        if (-not $current) {
            Write-Host "  [--] $binding not present" -ForegroundColor DarkGray
            continue
        }

        if ($current.Enabled -eq $false) {
            Write-Host "  [OK] $binding already disabled" -ForegroundColor DarkGray
            continue
        }

        if ($WhatIf) {
            Write-Host "  [PREVIEW] Would disable: $binding" -ForegroundColor Cyan
        } else {
            try {
                Disable-NetAdapterBinding -Name $adapter -ComponentID $binding -ErrorAction Stop
                Write-Host "  [OFF] $binding disabled" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host "  [ERR] Failed to disable $binding`: $_" -ForegroundColor Red
                $errorCount++
            }
        }
    }
}

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "Done. Disabled: $successCount | Skipped: $skipCount | Errors: $errorCount" -ForegroundColor Cyan

if ($errorCount -gt 0) {
    Write-Host "Some bindings failed. Run as Administrator if you haven't." -ForegroundColor Yellow
}
