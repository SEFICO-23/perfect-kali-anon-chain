# VPN-over-Tor — The nftables Fix

This is the core technical breakthrough of the whole setup.
Without this, Mullvad and Tor deadlock each other.

---

## The Chicken-and-Egg Problem

When Mullvad enters "Connecting" state, it immediately applies a strict nftables
firewall that drops ALL outbound traffic except:
- The specific relay IP it's trying to reach
- The Mullvad API server IP

This kills Tor's existing circuits and prevents new ones from being built.
But Mullvad needs Tor to connect. Deadlock.

```
Mullvad "Connecting" → nftables drops everything → Tor circuits die
Tor dead → proxychains4 can't route Mullvad's TCP connection → Mullvad stuck
```

---

## Mullvad's nftables Ruleset

Inspect it yourself:

```bash
sudo nft list table inet mullvad
```

The key parts:

```nft
table inet mullvad {
    chain output {
        type filter hook output priority filter; policy drop;  # DROP all by default
        oif "lo" accept                # Allow loopback
        ct mark 0x00000f41 accept      # Allow traffic with this conntrack mark
        ...
        oif "wg0-mullvad" accept       # Allow traffic through the tunnel
        reject                         # Reject everything else
    }

    chain input {
        type filter hook input priority filter; policy drop;
        ct mark 0x00000f41 accept      # Same bypass mark for incoming
        ...
    }

    chain mangle {
        type route hook output priority mangle; policy accept;
        # Mullvad's own split-tunnel: cgroup 5087041 gets the bypass mark
        meta cgroup 5087041 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
    }
}
```

`ct mark 0x00000f41` is Mullvad's internal bypass mechanism.
Traffic with this conntrack mark is allowed through the firewall.
This is how Mullvad's split-tunnel feature works — exempted apps get this mark.

---

## The Fix: Mark Tor's Traffic

We create a separate nftables table that runs BEFORE Mullvad's filter chain
and marks all traffic from UID 104 (the `debian-tor` user) with `ct mark 0x00000f41`.

Mullvad's output chain then sees `ct mark 0x00000f41` and accepts Tor's packets.

```bash
sudo cp scripts/tor-exempt-nft.sh /etc/tor-exempt-nft.sh
sudo chmod +x /etc/tor-exempt-nft.sh
sudo /etc/tor-exempt-nft.sh
```

Content:

```bash
#!/bin/bash
# Remove any existing table first (idempotent)
nft delete table inet tor_exempt 2>/dev/null

nft add table inet tor_exempt

# Type "route" allows influencing routing decisions (not just filter)
# Priority "mangle" = -150, which runs AFTER conntrack (-200) but BEFORE filter (0)
nft add chain inet tor_exempt mark_tor \
    '{ type route hook output priority mangle; policy accept; }'

# Mark all outbound packets from UID 104 (debian-tor) with:
# - ct mark 0x00000f41: Mullvad firewall bypass
# - meta mark 0x6d6f6c65: routing bypass (use eth0, not wg0-mullvad)
# Counter is for debugging — shows packets are matching
nft add rule inet tor_exempt mark_tor \
    meta skuid 104 ct mark set 0x00000f41 meta mark set 0x6d6f6c65 counter
```

---

## Why Priority -150 (Mangle), Not -200?

This was the hardest bug to find. Original attempt used priority -200:

```bash
# WRONG — races with conntrack
nft add chain inet tor_exempt mark_tor '{ type filter hook output priority -200; policy accept; }'
```

At priority -200 (`NF_IP_PRI_CONNTRACK`), our chain runs at the **same priority**
as Linux's conntrack module, which creates the connection tracking entry.

In nftables, `ct mark set X` sets the mark on the **conntrack entry**.
If the conntrack entry doesn't exist yet (because conntrack hasn't run),
`ct mark set` is a no-op — the mark goes nowhere.

```
Priority -200: our chain races conntrack → entry may not exist → ct mark does nothing
Priority -150: conntrack always runs first → entry exists → ct mark works
```

Mullvad's own split-tunnel uses priority **mangle (-150)** for exactly this reason.

---

## Why `meta mark` Is Also Needed

Even if the ct mark bypasses Mullvad's **firewall**, there's still the **routing** problem.

Mullvad installs policy routing rules:
```bash
ip rule show
# ...
# 32765: from all fwmark 0x6d6f6c65 lookup main  ← bypass table
# 32766: from all lookup main
# 32767: from all lookup default
```

When Mullvad is connected, all traffic without `fwmark 0x6d6f6c65` gets routed
through `wg0-mullvad`. But wg0-mullvad needs Tor to exist — circular again.

Setting `meta mark set 0x6d6f6c65` ("mole" in ASCII — Mullvad's own routing mark)
tells the kernel: *route this packet via the main routing table, not the VPN tunnel.*

This makes Tor's traffic go directly to `eth0` → internet → Tor guard nodes.

```
Without meta mark:  Tor → routing → wg0-mullvad → needs Tor → deadlock
With meta mark:     Tor → routing → eth0 → internet → Tor guard → works
```

---

## Why Chain Type `route` Not `filter`?

The `type route` chain type has a special property in nftables:
it can influence the routing decision for the packet.

Specifically, setting `meta mark` (fwmark) in a `route` chain causes the kernel
to re-evaluate the routing for that packet using the new mark. In a `filter` chain,
the fwmark is set but the routing decision has already been made — too late.

This is the same reason Mullvad uses `type route` for its own mangle chain.

---

## Verify It's Working

```bash
sudo nft list table inet tor_exempt
```

```
table inet tor_exempt {
    chain mark_tor {
        type route hook output priority mangle; policy accept;
        meta skuid 104 ct mark set 0x00000f41 meta mark set 0x6d6f6c65 counter packets 409 bytes 268828
    }
}
```

The **counter** should be non-zero and increasing while Tor is active.
If it's 0, the rule isn't matching — check Tor is running as UID 104:

```bash
ps -o uid,comm -p $(pgrep tor)
# uid 104  tor
```

---

## Two-Mark Summary

| Mark | Hex | ASCII | Purpose |
|------|-----|-------|---------|
| `ct mark` | `0x00000f41` | — | Mullvad firewall bypass (allow through output/input chains) |
| `meta mark` (fwmark) | `0x6d6f6c65` | "mole" | Mullvad routing bypass (use eth0, not wg0-mullvad) |

Both are required. One fixes the firewall. The other fixes the routing.
