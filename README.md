# Kali Anon Chain

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: WSL2](https://img.shields.io/badge/Platform-WSL2-purple.svg)](#requirements)
[![VPN: Mullvad](https://img.shields.io/badge/VPN-Mullvad-green.svg)](https://mullvad.net)

> **Multi-layer anonymization chain for Kali Linux on WSL2 (Windows).**
> Boots with plain networking. Activate anonymization on demand: `sudo anon-chain on`.

Targets see a clean Mullvad VPN IP — not a Tor exit node, not your ISP. Anti-bot systems (Cloudflare, Amazon, etc.) let you through. Your ISP sees only encrypted WireGuard to a Mullvad server. No single node in the chain sees both your identity and your destination.

---

## v2.0 — On-Demand Architecture

v1.0 ran the full anonymization chain at boot. This caused **persistent networking failures on WSL2** due to:

- **nftables/iptables kernel deadlocks** — WSL2's `iptables-nft` backend conflicts with direct `nft` commands, deadlocking the netfilter subsystem
- **Race conditions** — Multiple systemd services (`kali-firewall`, `kali-dns`, `networking`) fighting over eth0 state, routes, and DNS
- **Gateway blocking** — Firewall rules dropping traffic to the WSL2 Hyper-V gateway

v2.0 fixes this with a clean separation:

| State | Boot (default) | `sudo anon-chain on` |
| --- | --- | --- |
| eth0 | UP with route | UP with route |
| Firewall | None | nftables `inet anon_chain` |
| VPN | Off | Mullvad connected |
| Tor | Off | Active |
| DNS | 8.8.8.8 (Google) | 10.64.0.1 (Mullvad tunnel) |

**Key design rule:** Boot is ALWAYS plain networking. Zero firewall rules. Zero iptables commands (ever). The anonymization chain is opt-in via a single command.

---

## Quick Start

```bash
# Inside Kali WSL2:
git clone https://github.com/SEFICO-23/perfect-kali-anon-chain.git
cd perfect-kali-anon-chain
sudo ./scripts/install.sh

# Then from Windows PowerShell:
wsl --shutdown
wsl -d kali-linux

# Verify plain networking:
ping -c1 8.8.8.8        # Should work immediately

# Need anonymization?
sudo anon-chain on       # Start VPN + Tor + hardening
sudo anon-chain off      # Back to plain
sudo anon-chain status   # Check current state
```

---

## The Chain (when ON)

```text
Your PC (Windows)
  │
  │  ISP sees: encrypted WireGuard to Mullvad entry relay
  ▼
Windows Mullvad App (WireGuard, Multihop entry→exit, DAITA + Lockdown)
  │
  │  WSL2 NAT bridge
  ▼
Kali Linux WSL2
  │
  │  proxychains4 SOCKS5 tunnel
  ▼
Tor Daemon (3 encrypted hops: guard → middle → exit)
  │
  │  TCP stream (Udp2Tcp obfuscation — looks like HTTPS)
  ▼
Mullvad Kali (WireGuard Multihop: entry relay → exit relay, via Udp2Tcp over Tor)
  │
  │  Target sees: clean Mullvad exit IP
  ▼
Target
```

The full path spans **6+ jurisdictions**: your ISP → Mullvad Windows entry → Mullvad Windows exit → 3 independent Tor relays → Mullvad Kali entry → Mullvad Kali exit → target.

### Why not just Tor?

Tor exit IPs are publicly listed and blocked everywhere — Cloudflare, Amazon, Google, most e-commerce sites. This chain exits through a Mullvad VPN relay instead, giving you a clean, unlisted IP while Tor provides the anonymity underneath.

### Why not just a VPN?

A single VPN is one hop — the provider knows your real IP and your traffic. Here, Mullvad (Windows) sees only Tor traffic. The Kali Mullvad relay sees only encrypted WireGuard — it can't link it to you because it came through Tor.

### Why multihop on both sides?

Multihop adds an extra relay on each VPN leg. The entry server sees your source IP but not your traffic destination. The exit server sees the destination but not your source. Even if one Mullvad server is compromised, the attacker only gets half the picture.

---

## Anti-Bot Bypass

Sites behind Cloudflare, Amazon, or Akamai block automated requests even with clean IPs — they fingerprint TLS handshakes (JA3/JA4), HTTP/2 framing, and JavaScript execution.

```bash
# Install bypass dependencies
sudo ./scripts/install-stealth-deps.sh

# Fetch with automatic tier escalation
./scripts/stealth-fetch.sh https://example.com --tier auto -v

# Force headless browser for JavaScript-heavy sites
./scripts/stealth-fetch.sh https://example.com --tier 2
```

**Tier 1** (curl-cffi) spoofs Chrome TLS fingerprints — fast, handles 80%+ of sites. **Tier 2** (Patchright) runs a patched Chromium — handles JavaScript challenges, Cloudflare Turnstile, Akamai sensor, and auto-resolves silent CAPTCHAs.

---

## Health Check

```bash
./scripts/health-check.sh         # Full check (services + network)
./scripts/health-check.sh --quick # Services only
./scripts/health-check.sh --fix   # Full check + auto-repair
```

Or manually:

```bash
# Mullvad connected via multihop
mullvad status

# Target sees clean Mullvad IP (not Tor exit)
curl https://ifconfig.me
curl https://check.torproject.org/api/ip        # IsTor: false

# Direct Tor path still available
proxychains4 curl https://check.torproject.org/api/ip   # IsTor: true
```

---

## Repository Structure

```text
scripts/
  install.sh               — v2.0 installer (disables legacy services, sets up systemd)
  anon-chain.sh            — on/off/status toggle (installed to /usr/local/bin/anon-chain)
  kali-boot-network.sh     — minimal boot networking (eth0 + route + DNS, NO firewall)
  kali-boot-fix.sh         — [DEPRECATED] v1.0 boot script (kept for reference)
  health-check.sh          — verify the full chain
  stealth-fetch.sh         — anti-bot bypass CLI
  install-stealth-deps.sh  — install anti-bot dependencies
  tor-exempt-nft.sh        — nftables: Tor bypasses Mullvad firewall
  kali-firewall.sh         — [DEPRECATED] v1.0 iptables isolation
  mullvad-hop-selector.sh  — interactive multihop relay selector
  mullvad-multihop-fix.sh  — multihop configuration fix
  windows/
    sync-to-kali.sh        — push files to Kali WSL
    pull-from-kali.sh      — pull output from Kali to Windows
    harden-adapters.ps1    — strip protocols from Windows adapters
    hop-selector.bat       — Windows launcher for hop selector
    hop-selector.sh        — WSL bridge for hop selector

lib/stealth_fetch/         — anti-bot bypass Python package

systemd/
  kali-network.service            — [NEW] v2.0 boot networking (After=networking.service)
  tor-exempt.service              — Tor bypass rules (started by anon-chain on)
  kali-dns.service                — [DEPRECATED] v1.0 DNS override
  kali-firewall.service           — [DEPRECATED] v1.0 iptables isolation
  mullvad-override.conf           — proxychains4 wrapper for mullvad-daemon
  mullvad-multihop.service        — multihop enforcement
  anon-chain-healthcheck.service  — post-boot health check

config/
  wsl.conf                 — WSL2 config (systemd=true, automount=true)
  proxychains4.conf        — strict_chain → Tor SOCKS5
  relay.conf               — multihop relay selection (entry/exit countries)

docs/
  01 through 09            — step-by-step setup guides
```

---

## Key Technical Details

| Problem | Solution |
| --- | --- |
| nftables + iptables deadlocks WSL2 kernel | v2.0 uses ONLY nftables. Zero iptables commands, ever. |
| Boot services fight over eth0/routes/DNS | Single `kali-network.service` runs `After=networking.service` |
| `kali-firewall.service` blocks WSL gateway | Disabled at install. Firewall only via `anon-chain on`. |
| `kali-dns.service` overwrites resolv.conf | Disabled at install. DNS managed by boot script / anon-chain. |
| eth0 reports "state DOWN" but works | WSL2 Hyper-V quirk — ignore link state, test with ping. |
| Mullvad blocks external DNS when connected | Use Mullvad tunnel DNS (10.64.0.1) when chain is ON. |
| Mullvad's nftables kills Tor circuits | Mark Tor traffic with `ct mark 0x00000f41` (Mullvad bypass mark) |
| DAITA prevents tunnel over Tor | Padded frames can't survive Udp2Tcp + Tor wrapping — OFF in Kali |

---

## Requirements

- Windows 10/11 with WSL2
- Kali Linux (`wsl --install kali-linux`)
- [Mullvad VPN](https://mullvad.net) account (Windows app + CLI in Kali)

---

## Contributing

Issues and PRs welcome. If you find a way to improve the chain or discover new edge cases, open an issue.

---

## License

MIT — see [LICENSE](LICENSE) for details.
