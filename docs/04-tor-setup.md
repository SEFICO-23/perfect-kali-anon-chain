# Tor Setup & Verification

Set up Tor as a SOCKS5 proxy that the rest of the chain routes through.

---

## Install Tor

```bash
sudo apt install -y tor proxychains4
```

---

## Enable Tor at Boot

```bash
# Enable the parent service (not the instance)
# tor@default.service has "PartOf=tor.service"
# You enable tor.service and it pulls tor@default with it
sudo systemctl enable tor.service
sudo systemctl start tor@default.service
```

> **Common mistake:** Running `systemctl enable tor@default` shows
> `enabled-runtime` — that's not persistent. You MUST enable `tor.service`
> (the parent) for Tor to start at every boot.

Check it's running:

```bash
systemctl status tor@default
# Look for: "Bootstrapped 100% (done): Done"
```

---

## Configure proxychains4

proxychains4 intercepts outbound TCP `connect()` calls via `LD_PRELOAD` and
routes them through a proxy chain. We use it to force Mullvad's daemon
through Tor.

```bash
sudo nano /etc/proxychains4.conf
```

The relevant section (rest of file can stay default):

```
# Chain type: strict means ALL proxies in list must be used in order
strict_chain

# Proxy DNS through the chain (prevents DNS leaks outside Tor)
proxy_dns

# Quiet mode — suppress "[proxychains] DLL init" messages
quiet_mode

[ProxyList]
# Route through local Tor SOCKS5
# Protocol MUST be socks5, not socks4 — Tor requires SOCKS5
socks5  127.0.0.1  9050
```

> **socks4 vs socks5:** SOCKS4 doesn't support hostname resolution through
> the proxy (only IP addresses). SOCKS5 supports both. Tor requires SOCKS5
> for `.onion` domains and for proper DNS-over-proxy. If you leave it as
> `socks4`, DNS leaks outside the Tor circuit.

---

## Verify Tor Works Standalone

Before wiring everything together, confirm Tor itself works:

```bash
proxychains4 curl https://check.torproject.org/api/ip
# Expected: {"IsTor":true,"IP":"<some tor exit IP>"}
```

```bash
# The direct exit (without proxychains4) should NOT be Tor
curl https://check.torproject.org/api/ip
# Expected: {"IsTor":false,"IP":"<your current exit IP>"}
```

---

## How Tor Works in This Setup

Tor runs as a system daemon under the `debian-tor` user (UID 104).
It listens on `127.0.0.1:9050` (SOCKS5).

```
Your application
     │
     │  LD_PRELOAD hook via proxychains4
     ▼
SOCKS5 connect() to 127.0.0.1:9050
     │
     ▼
Tor Guard Node (first hop — encrypted with 3 layers)
     │
     ▼
Tor Middle Relay (second hop — 2 layers)
     │
     ▼
Tor Exit Node (third hop — 1 layer, then cleartext to destination)
     │
     ▼
Destination
```

The key property: **no single node sees both your IP and your destination**.
- Guard knows your IP but not the destination
- Exit knows the destination but not your IP
- Middle knows neither

---

## Why proxychains4 and Not torsocks?

`torsocks` is more aggressive — it blocks ALL UDP including local sockets.

Mullvad's daemon uses UDP internally:
- WireGuard is UDP-based
- The `Udp2Tcp` obfuscation module binds a local UDP socket
- Even with Tor wrapping the outbound TCP, local UDP bind must succeed

`torsocks` blocks `bind()` on UDP sockets → Mullvad fails to start.

`proxychains4` only intercepts `connect()` calls → local UDP binds work fine.

```
torsocks:    hooks connect() AND blocks UDP bind() → Mullvad crashes
proxychains4: hooks connect() only                → Mullvad works
```
