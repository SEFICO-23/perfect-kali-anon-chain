# Verification & Troubleshooting

How to confirm everything is working, and how to diagnose when it's not.

---

## Full Verification Checklist

Run these from inside Kali after boot:

```bash
# 1. All services running
systemctl is-active kali-dns tor-exempt tor@default mullvad-daemon

# 2. DNS is a real file (not dangling symlink)
ls -la /etc/resolv.conf      # Should show -rw-r--r-- (regular file, not l-> link)
cat /etc/resolv.conf         # Shows 9.9.9.9 before Mullvad connects, 10.64.0.1 after — both correct

# 3. nftables exemption in place
sudo nft list table inet tor_exempt  # Should show counter with packets > 0

# 4. Tor is bootstrapped
journalctl -u tor@default --no-pager -n 5
# Look for: Bootstrapped 100% (done): Done

# 5. Mullvad connected
mullvad status
# Connected, Relay: <exit-relay> via <entry-relay>, Features: Udp2Tcp

# 6. Exit IP is Mullvad exit relay (not Tor)
curl https://check.torproject.org/api/ip
# {"IsTor":false,"IP":"<mullvad IP>"}

# 7. Mullvad confirms it
curl https://am.i.mullvad.net/json
# mullvad_exit_ip: true, blacklisted: false

# 8. Direct Tor path still works
proxychains4 curl https://check.torproject.org/api/ip
# {"IsTor":true,"IP":"<tor exit>"}
```

---

## Common Issues

### `mullvad status` → "Management RPC server or client error"

The daemon isn't running.

```bash
sudo systemctl status mullvad-daemon
sudo systemctl start mullvad-daemon
sleep 5
mullvad status
```

If it starts but immediately stops, check why:

```bash
journalctl -u mullvad-daemon --no-pager -n 20
```

---

### `curl: (6) Could not resolve host`

DNS is broken. Check:

```bash
cat /etc/resolv.conf
```

If empty or pointing to a non-existent path:

```bash
sudo rm -f /etc/resolv.conf
sudo printf 'nameserver 9.9.9.9\nnameserver 149.112.112.112\n' > /etc/resolv.conf
```

Then reconnect Mullvad (it will replace this with its own DNS when connected):

```bash
sudo mullvad connect
```

**Root cause:** `/etc/resolv.conf` was a symlink to `/run/resolvconf/resolv.conf`.
The `/run/` tmpfs is wiped at boot. `kali-dns.service` fixes this by doing
`rm -f /etc/resolv.conf` (removes symlink) before writing. If you see this
repeatedly, check that `kali-dns.service` is enabled and running.

---

### Mullvad stuck in "Connecting" / Tor circuit failures

```
Failed to find node for hop #1 of our path. Discarding this circuit.
```

Mullvad's firewall is blocking Tor's outbound connections.

Check `tor-exempt` is active:

```bash
systemctl is-active tor-exempt
sudo nft list table inet tor_exempt
```

If the table is missing (counter shows 0 or table not found):

```bash
sudo /etc/tor-exempt-nft.sh    # Re-apply nftables rules
sudo systemctl restart tor@default
sleep 5
mullvad connect
```

---

### Mullvad → "Blocked: Failed to set system DNS server"

Mullvad can't write its DNS to `/etc/resolv.conf`. Usually caused by a
dangling symlink.

```bash
ls -la /etc/resolv.conf   # If it shows lrwxrwxrwx → fix:
sudo rm -f /etc/resolv.conf
sudo printf 'nameserver 9.9.9.9\n' > /etc/resolv.conf
sudo mullvad disconnect && sudo mullvad connect
```

---

### `tor@default` shows `enabled-runtime` after reboot

You enabled the instance instead of the parent:

```bash
# Wrong:
sudo systemctl enable tor@default   # gives "enabled-runtime"

# Correct:
sudo systemctl enable tor.service   # gives "enabled" (persistent)
```

---

### Mullvad connects but `IsTor: true`

This means you're going through Tor directly, not through Mullvad-in-Kali.
Likely Mullvad is disconnected and your traffic is hitting the default
proxychains4 route (straight Tor).

```bash
mullvad status   # Should say Connected, not Disconnected
mullvad connect  # If disconnected
```

---

### Mullvad tunnel won't establish (DAITA enabled)

If Mullvad is stuck connecting and you have DAITA enabled in Kali:

```bash
sudo mullvad tunnel get
# If DAITA shows "on" → that's the problem
```

DAITA's padded frames are incompatible with Udp2Tcp + Tor wrapping.
This is a hard incompatibility, not a tuning issue.

```bash
sudo mullvad tunnel set daita off
sudo mullvad reconnect
```

DAITA should remain **ON** in the Windows Mullvad app (where it works normally)
and **OFF** in Kali.

---

### Quantum resistance error

```
Failed while negotiating ephemeral peer - Connection refused (os error 111)
```

Quantum resistance must be OFF in Kali's Mullvad:

```bash
sudo mullvad tunnel set quantum-resistant off
sudo mullvad reconnect
```

---

## Diagnostic Commands Reference

```bash
# Full service overview
systemctl is-active kali-dns tor-exempt tor@default tor.service mullvad-daemon

# Mullvad daemon live logs
journalctl -u mullvad-daemon -f

# Tor live logs
journalctl -u tor@default -f

# nftables full ruleset (see both Mullvad and tor_exempt tables)
sudo nft list ruleset

# Mullvad's current settings
mullvad relay get
mullvad anti-censorship get
mullvad tunnel get
mullvad auto-connect get
mullvad dns get

# Check what IP you're exiting from
curl https://am.i.mullvad.net/json | python3 -m json.tool
```

---

## The "Cold Start" Recovery Procedure

If everything is broken after a fresh boot:

```bash
# Step 1: Fix DNS
sudo rm -f /etc/resolv.conf
sudo printf 'nameserver 9.9.9.9\nnameserver 149.112.112.112\n' > /etc/resolv.conf

# Step 2: Apply nftables exemption
sudo /etc/tor-exempt-nft.sh

# Step 3: Restart Tor
sudo systemctl restart tor@default
sleep 5

# Step 4: Restart Mullvad daemon
sudo systemctl restart mullvad-daemon
sleep 10

# Step 5: Check
mullvad status
curl https://ifconfig.me
```
