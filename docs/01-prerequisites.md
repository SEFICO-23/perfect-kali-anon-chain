# Prerequisites

Everything you need before starting. Read this fully before touching anything.

---

## Hardware & OS

- **Windows 10 (build 19041+) or Windows 11**
- **Virtualization enabled in BIOS** (Intel VT-x or AMD-V)
- Verify: Task Manager → Performance → CPU → check "Virtualization: Enabled"

---

## Software to Install First

### 1. WSL2

Open PowerShell as Administrator:

```powershell
wsl --install
wsl --set-default-version 2
```

Reboot when prompted.

### 2. Kali Linux

```powershell
wsl --install kali-linux
```

Or download from the [Microsoft Store](https://apps.microsoft.com/store/detail/kali-linux).

On first launch, create a user (e.g. `kali` / your preferred password).
Substitute your chosen username wherever this guide references the Kali user.

### 3. Mullvad VPN (Windows App)

Download from [mullvad.net/download](https://mullvad.net/en/download/vpn/windows).

You need a Mullvad account. Mullvad sells anonymous subscriptions — no email required.
Top up at [mullvad.net/account](https://mullvad.net/en/account).

### 4. Git Bash (Windows)

Download from [git-scm.com](https://git-scm.com/download/win).
Used to run the sync scripts on the Windows side.

---

## Knowledge Prerequisites

You should be comfortable with:

- Basic Linux terminal commands (`cd`, `cat`, `sudo`, `systemctl`)
- What a VPN and Tor are at a conceptual level
- What WSL2 is (a real Linux kernel running inside a lightweight Hyper-V VM)

You do **not** need to understand nftables, WireGuard internals, or systemd deeply —
this guide explains every step.

---

## Understanding WSL2 Networking

WSL2 runs as a virtual machine with its own network adapter (`vEthernet (WSL)`).
Traffic from Kali flows:

```
Kali eth0 → WSL NAT (172.x.x.1 gateway) → Windows vEthernet (WSL) → Windows routing → Internet
```

Because of this, **all Kali traffic passes through Windows** — meaning Windows
Mullvad automatically wraps all WSL traffic. This is intentional and is
the foundation of the first layer.

---

## Accounts Needed

| Service | Purpose | Cost |
|---------|---------|------|
| Mullvad VPN | Layer 1 (Windows) + Layer 4 (Kali) | ~€5/month |
| GitHub | To host this setup (optional) | Free |

Mullvad allows up to 5 devices per account. This setup uses 2:
your Windows machine + Kali (registered as a separate device).

---

## What You'll Have at the End

```
Boot Kali → auto-connected → 5 anonymity layers → clean exit IP
```

No manual steps after initial setup. Persistent across reboots.
