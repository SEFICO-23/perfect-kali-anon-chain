# Boot Persistence

Make everything survive a `sudo reboot` with zero manual steps.

---

## The Target State

After any reboot, opening a Kali terminal should give you:

```bash
mullvad status
# Connected
#     Relay: <exit-relay> via <entry-relay>
#     Features: Udp2Tcp
```

No `mullvad connect`, no DNS fix, no nftables setup. Fully automatic.

---

## Boot Order

Services must start in this exact order:

```
kali-dns.service          (Before=network.target)
      │
      ▼
tor-exempt.service        (After=network.target, Before=mullvad-daemon.service)
      │
      ▼
tor.service               (After=network-online.target)
 └─ tor@default.service   (PartOf=tor.service)
      │
      ▼
mullvad-daemon.service    (After=tor@default.service tor-exempt.service)
      │
      ▼
Auto-connect fires → Mullvad connects through Tor
      │
      ▼
mullvad-multihop.service  (After=mullvad-daemon.service tor@default.service)
  → Enforces RS→PT multihop if auto-connect fell back to single-hop
```

---

## Step 1 — tor-exempt service

```bash
sudo cp scripts/tor-exempt-nft.sh /etc/tor-exempt-nft.sh
sudo chmod +x /etc/tor-exempt-nft.sh
sudo cp systemd/tor-exempt.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable tor-exempt.service
```

The service (`ExecStop=`) also cleans up the nftables table when stopped:

```ini
[Unit]
Description=Tor nftables exemption for Mullvad VPN-over-Tor
Before=mullvad-daemon.service
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/tor-exempt-nft.sh
RemainAfterExit=yes
ExecStop=/usr/sbin/nft delete table inet tor_exempt

[Install]
WantedBy=multi-user.target
```

---

## Step 2 — Mullvad daemon proxychains4 override

```bash
sudo mkdir -p /etc/systemd/system/mullvad-daemon.service.d/
sudo cp systemd/mullvad-override.conf \
    /etc/systemd/system/mullvad-daemon.service.d/override.conf
sudo systemctl daemon-reload
```

Content of `mullvad-override.conf`:

```ini
[Unit]
# Wait for both Tor and the nftables exemption before starting
After=tor@default.service tor-exempt.service
Wants=tor@default.service tor-exempt.service

[Service]
# Clear the original ExecStart, then override with proxychains4 wrapper
ExecStart=
ExecStart=/usr/bin/proxychains4 -q /usr/bin/mullvad-daemon -v --disable-stdout-timestamps
```

> **Why `ExecStart=` (empty line) before the new value?**
> In systemd drop-in overrides, you can't replace a `ExecStart` by just
> adding a new one — that would create two start commands. The empty
> `ExecStart=` clears the list first, then the second line sets the new value.

---

## Step 3 — Enable Tor persistently

```bash
# Enable tor.service (NOT tor@default — that's the instance, not the parent)
sudo systemctl enable tor.service
```

```bash
# Verify
systemctl is-enabled tor.service        # Should say: enabled
systemctl is-enabled tor@default.service # May say: enabled-runtime (that's fine)
```

> `tor@default` is a template instance (the `@` denotes a template).
> Template instances are controlled by their parent `tor.service`.
> Enabling the instance directly only persists for the current boot session.
> Enable the parent, and the instance comes along.

---

## Step 4 — Mullvad auto-connect

```bash
sudo mullvad auto-connect set on
sudo mullvad auto-connect get
# Autoconnect: on
```

Without this, the daemon starts at boot but sits idle — you'd need to run
`mullvad connect` manually every time.

---

## Step 5 — mullvad-multihop enforcement

Mullvad auto-connects on boot through `proxychains4 → Tor`. There's a race condition:
if Tor circuits aren't fully established when Mullvad tries the multihop handshake, it
silently falls back to single-hop and **persists that change to settings.json**.

This service runs after `mullvad-daemon`, checks if multihop got disabled, and re-enables it.

```bash
# Script: /etc/mullvad-multihop-fix.sh
# Service: /etc/systemd/system/mullvad-multihop.service

sudo cp scripts/mullvad-multihop-fix.sh /etc/mullvad-multihop-fix.sh
sudo chmod +x /etc/mullvad-multihop-fix.sh
sudo cp systemd/mullvad-multihop.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mullvad-multihop.service
```

The service unit:

```ini
[Unit]
Description=Enforce Mullvad multihop RS->PT after boot
After=mullvad-daemon.service tor@default.service
Wants=mullvad-daemon.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/etc/mullvad-multihop-fix.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Logs at `/var/log/mullvad-multihop-fix.log`. Check with:

```bash
systemctl status mullvad-multihop.service
cat /var/log/mullvad-multihop-fix.log
```

---

## Step 6 — kali-dns and kali-firewall

Already covered in [doc 02](02-kali-wsl2-setup.md). Confirm they're enabled:

```bash
systemctl is-enabled kali-dns kali-firewall tor-exempt mullvad-daemon mullvad-multihop tor.service
# Should all say: enabled
```

---

## Full Installation at Once

If you're setting up from scratch, run these in order:

```bash
# 1. Copy all service files
sudo cp systemd/kali-dns.service /etc/systemd/system/
sudo cp systemd/kali-firewall.service /etc/systemd/system/
sudo cp systemd/tor-exempt.service /etc/systemd/system/
sudo mkdir -p /etc/systemd/system/mullvad-daemon.service.d/
sudo cp systemd/mullvad-override.conf /etc/systemd/system/mullvad-daemon.service.d/override.conf

# 2. Copy scripts
sudo cp scripts/tor-exempt-nft.sh /etc/tor-exempt-nft.sh
sudo chmod +x /etc/tor-exempt-nft.sh
sudo cp scripts/kali-firewall.sh /etc/kali-firewall.sh
sudo chmod +x /etc/kali-firewall.sh
sudo cp scripts/mullvad-multihop-fix.sh /etc/mullvad-multihop-fix.sh
sudo chmod +x /etc/mullvad-multihop-fix.sh

# 3. Enable all services
sudo systemctl daemon-reload
sudo systemctl enable kali-dns kali-firewall tor-exempt mullvad-multihop tor.service

# 4. Enable Mullvad auto-connect + set multihop
sudo mullvad auto-connect set on
sudo mullvad relay set location pt
sudo mullvad relay set multihop on
sudo mullvad relay set entry location rs beg

# 5. Apply immediately (no reboot needed)
sudo systemctl start kali-dns kali-firewall tor-exempt
sudo systemctl restart tor@default
sudo systemctl restart mullvad-daemon
sleep 15
sudo systemctl start mullvad-multihop
mullvad status
```

---

## Confirm After Reboot

```bash
sudo reboot
# ... wait for Kali to restart (give it ~30s for all services) ...
mullvad status               # Should show: Connected, pt-lis-wg-XXX via rs-beg-wg-XXX
mullvad relay get            # Should show: Multihop state: enabled, entry: city beg, rs
curl https://ifconfig.me     # Should show Mullvad Portugal exit IP
systemctl is-active kali-dns kali-firewall tor-exempt tor@default mullvad-daemon mullvad-multihop
# All should say: active
cat /var/log/mullvad-multihop-fix.log  # Check enforcement ran
```
