# Mullvad in Kali

Install the Mullvad CLI inside Kali and register it as a separate device
on your Mullvad account.

---

## Install Mullvad CLI

```bash
# Add Mullvad repository
sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc \
    https://repository.mullvad.net/deb/mullvad-keyring.asc

echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$( dpkg --print-architecture )] \
    https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/mullvad.list

sudo apt update
sudo apt install -y mullvad-vpn
```

This installs:
- `mullvad` — the CLI client
- `mullvad-daemon` — the background service that manages the tunnel

---

## Register Kali as a Mullvad Device

```bash
# Log in with your Mullvad account number (16 digits, no spaces)
sudo mullvad account login YOUR_ACCOUNT_NUMBER

# Verify — should show your account and a device name like "Worthy Gecko"
sudo mullvad account get
```

Mullvad allows up to 5 devices per account. Kali registers as a separate device
from your Windows Mullvad app. Check your device count at
[mullvad.net/account](https://mullvad.net/en/account).

---

## Configure Mullvad in Kali

```bash
# Enable multihop — two Mullvad relays in chain for jurisdiction separation
# Choose your own entry and exit countries (see relay selection guide in README)
# Entry: pick a non-Eyes, non-EU country close to infrastructure
# Exit: pick a country with clean, unblacklisted IP pools
sudo mullvad relay set tunnel-protocol wireguard
sudo mullvad relay set location <exit-country-code>          # e.g. pt, nl, ch
sudo mullvad relay set tunnel wireguard entry-location <entry-country-code>  # e.g. rs, md, is

# Use Udp2Tcp anti-censorship mode
# This wraps WireGuard UDP inside TCP — required for routing through Tor,
# because Tor only transports TCP streams
sudo mullvad anti-censorship set udp2tcp

# Disable DAITA — padded DAITA frames cannot survive being wrapped in
# Udp2Tcp and pushed through Tor cells. This is a hard incompatibility
# that completely prevents tunnel establishment. Keep DAITA ON for Windows only.
sudo mullvad tunnel set daita off

# Disable quantum resistance
# Quantum resistance requires connecting to an API endpoint INSIDE the tunnel
# before the tunnel is established — impossible when the tunnel depends on Tor.
# The ephemeral peer negotiation hangs → connection never establishes.
sudo mullvad tunnel set quantum-resistant off

# Enable auto-connect — connect automatically when the daemon starts
sudo mullvad auto-connect set on

# Verify settings
sudo mullvad relay get
sudo mullvad anti-censorship get
sudo mullvad tunnel get
sudo mullvad auto-connect get
```

---

## Why Udp2Tcp Is Required

WireGuard is a UDP protocol. Tor only carries TCP streams.

Without Udp2Tcp:
```
WireGuard (UDP) → proxychains4 intercepts connect() → Tor (TCP only) → FAIL
```

With Udp2Tcp:
```
WireGuard (UDP) → Mullvad's Udp2Tcp module → TCP stream → proxychains4 → Tor → Relay
```

Udp2Tcp creates a local UDP listener and connects to the relay via TCP.
proxychains4 intercepts the TCP `connect()` call and routes it through Tor.

---

## Why DAITA Must Be Off in Kali

DAITA (Defense Against AI-guided Traffic Analysis) adds padding to WireGuard
packets to prevent traffic fingerprinting. However, these padded frames cannot
survive the double wrapping of Udp2Tcp + Tor:

```
DAITA padded frame → Udp2Tcp wraps in TCP → Tor cells fragment/reassemble → corrupt
```

This isn't a tuning issue — it's a hard incompatibility. DAITA completely prevents
tunnel establishment when routed through Tor. Keep DAITA **ON** for the Windows
Mullvad app (where it works normally) and **OFF** for the Kali side.

---

## Why Quantum Resistance Must Be Off

Mullvad's quantum resistance (post-quantum WireGuard) works by:
1. Establishing an initial WireGuard connection
2. Connecting to an API at `10.64.0.1:1337` INSIDE the tunnel
3. Negotiating ephemeral post-quantum keys
4. Re-establishing the tunnel with new keys

Step 2 requires the tunnel to be up to reach `10.64.0.1`. But if the tunnel
depends on Tor (which isn't up yet), the tunnel can't establish.

```
Error: Failed while negotiating ephemeral peer - Connection refused (os error 111)
```

This is a circular dependency: tunnel needs quantum API, quantum API needs tunnel.

**Windows Mullvad can have quantum resistance ON** — it doesn't route through Tor.
Only Kali's Mullvad needs it OFF.

---

## Test Manual Connection (Before Persisting)

```bash
sudo mullvad connect
sleep 10
sudo mullvad status
```

Expected:
```
Connected
    Relay:    <exit-relay> via <entry-relay>
    Features: Udp2Tcp
```

Check exit IP:
```bash
curl https://ifconfig.me     # Should show Mullvad exit relay IP
curl https://check.torproject.org/api/ip   # IsTor: false
```

If this works, proceed to [VPN-over-Tor — The nftables Fix](06-vpn-over-tor-nftables.md).

If Mullvad stays in "Connecting" state, Tor's traffic is being blocked by
Mullvad's own firewall — see the next doc for the fix.
