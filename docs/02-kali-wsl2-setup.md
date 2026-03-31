# Kali WSL2 Setup & Hardening

This configures Kali to be isolated from Windows — no shared filesystem,
no path bleed, no pivot surface if Kali is ever compromised.

---

## Step 1 — First Boot & Update

Launch Kali from the Start Menu. Complete the initial user setup, then:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y tor proxychains4 nftables curl wget git python3 nmap
```

---

## Step 2 — WSL Configuration (`/etc/wsl.conf`)

This is the most important config file. It controls how WSL2 integrates with Windows.
We want **maximum isolation**.

```bash
sudo nano /etc/wsl.conf
```

Paste exactly:

```ini
[automount]
enabled = false          # Disable automatic Windows drive mounting (/mnt/c etc.)
                         # Prevents Kali from accessing Windows filesystem

[interop]
enabled = false          # Disable launching Windows executables from Kali
appendWindowsPath = false # Prevent Windows PATH from leaking into Kali

[boot]
systemd = true           # Enable systemd — required for our service-based setup

[network]
generateResolvConf = false  # Prevent WSL from overwriting /etc/resolv.conf
                             # We manage DNS ourselves via kali-dns.service
```

**Why these matter:**
- `automount = false` — A compromised Kali cannot read `C:\Users\you\Documents`
- `interop = false` — Prevents path injection attacks through Windows binaries
- `generateResolvConf = false` — WSL's auto-DNS would overwrite our static config

Shut down WSL completely to apply:

```powershell
# Run in PowerShell (Windows side)
wsl --shutdown
```

Restart Kali.

---

## Step 3 — Static DNS Service

WSL resets `/etc/resolv.conf` on boot. We need DNS before any service starts.

**Problem:** `/etc/resolv.conf` is often a symlink to `/run/resolvconf/resolv.conf`.
The `/run/` directory is a tmpfs — it's wiped on every boot. The symlink becomes
dangling before our services can write to it.

**Fix:** Replace the symlink with a real file, and write a service that does this
every boot:

```bash
# First, fix right now
sudo rm -f /etc/resolv.conf
sudo printf 'nameserver 9.9.9.9\nnameserver 149.112.112.112\n' > /etc/resolv.conf
```

Copy the service file:

```bash
sudo cp systemd/kali-dns.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kali-dns.service
sudo systemctl start kali-dns.service
```

Content of `kali-dns.service`:

```ini
[Unit]
Description=Write static DNS resolv.conf
DefaultDependencies=no
Before=network.target

[Service]
Type=oneshot
# rm -f first: removes any dangling symlink before writing
ExecStart=/bin/bash -c "rm -f /etc/resolv.conf && printf 'nameserver 9.9.9.9\nnameserver 149.112.112.112\n' > /etc/resolv.conf"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

> **Why `printf` instead of `echo -e`?**
> `echo -e nameserver 9.9.9.9\nnameserver ...` is parsed by bash as two commands:
> `echo -e nameserver 9.9.9.9` and `nameserver ... > file`.
> The second line tries to run `nameserver` as a program and fails.
> `printf` handles escape sequences correctly inside a double-quoted string.

---

## Step 4 — Host Isolation Firewall

Block all traffic to/from the Windows host IP. This prevents a compromised Kali
from pivoting to your Windows files, credentials, or other processes.

```bash
sudo cp scripts/kali-firewall.sh /etc/kali-firewall.sh
sudo chmod +x /etc/kali-firewall.sh
sudo cp systemd/kali-firewall.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kali-firewall.service
sudo systemctl start kali-firewall.service
```

The firewall script auto-detects your WSL gateway IP at runtime via `ip route`.
You do not need to edit the script. To verify your gateway:

```bash
ip route | grep default   # Shows gateway IP
```

---

## Step 5 — Verify Isolation

```bash
# WSL automount should be gone
ls /mnt/   # Should be empty or only contain 'wsl'

# Windows PATH should not appear
echo $PATH  # Should contain only Linux paths

# DNS should work
curl https://example.com   # Should succeed
```

---

## Summary of What This Does

| Setting | Effect |
|---------|--------|
| `automount = false` | Kali cannot see `C:\`, `D:\` etc. |
| `interop = false` | Kali cannot run `.exe` files |
| `appendWindowsPath = false` | No Windows PATH pollution |
| `systemd = true` | Full service management at boot |
| `generateResolvConf = false` | We own DNS, WSL doesn't touch it |
| `kali-dns.service` | Quad9 DNS always available at boot |
| `kali-firewall.service` | Windows host IP hard-blocked |
