# Anti-Bot Bypass Layer

The VPN-over-Tor chain gives you clean Mullvad IPs — not Tor exit nodes.
But anti-bot systems fingerprint at deeper layers than IP reputation.
This module solves that.

---

## The Problem

Even with a clean IP, standard `curl` and Python `requests` get blocked because:

| Detection Layer | What They Check | curl Detected? |
|----------------|-----------------|----------------|
| TLS fingerprint (JA3/JA4) | Cipher suites, extension order, ALPN | Yes — curl has a unique fingerprint |
| HTTP/2 fingerprint | SETTINGS frames, HPACK header order, window sizes | Yes — differs from all browsers |
| JavaScript challenges | Execute JS, solve Turnstile/CAPTCHA | curl can't execute JS at all |
| Header consistency | Sec-Ch-Ua must match User-Agent must match TLS | curl sends no Sec-Ch-Ua headers |

## The Solution: Two-Tier Bypass

```
Tier 1: curl-cffi      → spoofs Chrome TLS at the C library level (fast, ~20MB)
  ↓ blocked?
Tier 2: Patchright      → full headless Chromium with binary-level patches (~250MB)
```

**Why two tiers?** Tier 1 handles 80%+ of sites (APIs, product pages, search results).
Tier 2 is only needed for sites that require JavaScript execution (Cloudflare Turnstile,
Akamai sensor data, interactive challenges). Using Tier 2 for everything would be
slow and resource-heavy.

---

## Installation

```bash
sudo ./scripts/install-stealth-deps.sh
```

This creates a Python venv at `/opt/kali-anon-chain/venv` and installs:
- **Tier 1**: `curl-cffi` (always installed)
- **Tier 2**: `patchright` + Chromium (optional, prompted — ~250MB)

---

## Usage

```bash
# Auto-escalate: try Tier 1, escalate if blocked
./scripts/stealth-fetch.sh https://amazon.com --tier auto -v

# Force a specific tier
./scripts/stealth-fetch.sh https://example.com --tier 1
./scripts/stealth-fetch.sh https://nowsecure.nl --tier 2

# Save output to file
./scripts/stealth-fetch.sh https://amazon.com -o page.html

# JSON output with metadata (tier used, block score, etc.)
./scripts/stealth-fetch.sh https://amazon.com --json

# Route through raw Tor (bypassing Mullvad — less clean IP)
./scripts/stealth-fetch.sh https://example.com --tor-direct

# Different browser profile
./scripts/stealth-fetch.sh https://example.com --browser safari
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--tier auto\|1\|2` | auto | Bypass tier (auto = escalate on block) |
| `--tor-direct` | off | Route through Tor SOCKS5 instead of Mullvad |
| `--browser` | chrome | Impersonation profile (chrome, chrome131, chrome136, safari) |
| `--header KEY:VAL` | — | Custom HTTP header (repeatable) |
| `--timeout N` | 30 | Request timeout in seconds |
| `-o FILE` | stdout | Save body to file |
| `--json` | off | JSON output with metadata |
| `-v` | off | Verbose (show tier attempts on stderr) |
| `--no-kill-switch` | off | Skip Mullvad check (UNSAFE) |
| `--no-rate-limit` | off | Skip per-domain delay |

---

## How It Works

### BrowserProfile — Fingerprint Consistency

Anti-bot systems cross-check multiple signals for consistency:
- TLS fingerprint must match the claimed browser version
- `Sec-Ch-Ua` header must match the `User-Agent`
- `Sec-Ch-Ua-Platform` must match the OS in the User-Agent
- Header ordering must match Chrome's actual order (Akamai checks this)

The `BrowserProfile` class bundles all of these together. When you select
`chrome131`, it auto-generates matching TLS target, User-Agent, Sec-Ch-Ua,
and 15+ headers in Chrome's exact order. Mismatches are impossible.

### BlockDetector — Scored Detection

Simple HTTP 403 checking misses most blocks:
- Amazon returns **200** with a CAPTCHA page
- Cloudflare adds `cf-mitigated: challenge` header to 200 responses
- Akamai serves JavaScript redirects with 200 status

The detector scores responses across multiple signals (status code, response
headers, body patterns, body size, cookie analysis) and returns a score from
0.0 (clean) to 1.0 (definitely blocked). Scores >= 0.5 trigger tier escalation.

### KillSwitch — Leak Prevention

Before every request:
1. Verify `mullvad status` shows Connected
2. Verify `wg0-mullvad` interface exists (binding target)
3. Verify `/etc/resolv.conf` points to safe DNS (Mullvad or Quad9)

If any check fails, the request is **refused** — fail closed, not fail open.

### SessionManager — Cookie Persistence

Per-domain cookie jars. Amazon's `session-id`, Cloudflare's `cf_clearance`,
and other session cookies persist across requests. Cookies transfer between
tiers on escalation (Tier 1 cookies are loaded into Tier 2's browser).

### RateLimiter — Per-domain Delays

Randomized delays (1.5-4.5 seconds) between requests to the same domain.
Fixed intervals are themselves a bot signature — the jitter makes the
pattern look human.

---

## Tier 1: curl-cffi

**What it does**: Impersonates Chrome/Safari at the TLS level by using a
modified libcurl linked against BoringSSL (Chrome's TLS library) instead
of OpenSSL.

**What it bypasses**: JA3/JA4 TLS fingerprinting, HTTP/2 frame fingerprinting,
basic bot detection based on TLS signatures.

**What it can't do**: Execute JavaScript, solve CAPTCHAs, handle Cloudflare
Turnstile or Akamai sensor challenges.

**Note**: curl-cffi only supports Chrome and Safari impersonation (BoringSSL-based).
Firefox uses NSS and is NOT supported. Never use a `--browser firefox` flag — the
TLS/header mismatch would be instantly detected.

---

## Tier 2: Patchright

**What it does**: Runs a full headless Chromium browser with compile-time
patches that remove automation signals at the C++ level.

**Why Patchright over playwright-stealth?** playwright-stealth only patches
JavaScript (`navigator.webdriver`, etc.). Modern anti-bot systems detect
at the Chrome DevTools Protocol (CDP) level and via binary-level signals.
Patchright patches the Chromium binary itself — same Playwright API,
drop-in replacement, but much harder to detect.

**What it bypasses**: Everything Tier 1 does, plus JavaScript challenges
(Cloudflare Turnstile, Akamai sensor), full DOM rendering, browser-level
cookie management.

**Limitations**: ~250MB install, ~5-10 seconds per request (vs <1s for Tier 1),
higher CPU/RAM usage.

### Challenge Auto-Resolution

Many anti-bot systems serve **silent JavaScript challenges** — invisible CAPTCHA-like
tests that execute in the browser and redirect to the real page on success. Common
examples:

| Provider | Challenge Marker | Behavior |
|----------|-----------------|----------|
| Amazon | `opfcaptcha` in page source | JS executes, validates browser, redirects |
| Cloudflare | `cf-challenge`, `_cf_chl_opt` | Turnstile widget or silent JS challenge |
| Cloudflare (legacy) | `jschl-answer` | JS math challenge, auto-submits form |
| Generic | `challenge-form` | Various JS-based validation |

Tier 2 detects these challenge pages and **waits for the JS to auto-resolve**
(up to 15 seconds). Because Patchright runs a real Chromium engine — not a
headless shell — the challenge JS sees a genuine browser environment and passes.

The flow:
1. Navigate to URL → receive challenge page (e.g., HTTP 202 + 2KB body)
2. Detect challenge markers in the response body
3. Wait for the browser JS to solve the challenge and trigger a redirect
4. Capture the real page content after redirect

This is why Tier 2 uses `headless=False` with `--headless=new` instead of
the default headless shell mode. The "new headless" runs the **full Chromium
binary** without a visible window, preserving the exact same JS engine,
rendering pipeline, and fingerprint as a real user's browser. The old
headless shell (`chrome-headless-shell`) is a stripped-down binary that
anti-bot systems can trivially identify.

> **Tested**: Amazon.com returns a full page (~976KB, 29 cookies) after
> the challenge auto-resolves in ~20 seconds through the full chain.

---

## DNS Safety

For the default path (traffic through Mullvad), DNS resolves through
Mullvad's internal DNS at `10.64.0.1`. No leak.

For `--tor-direct` mode, the proxy URL is `socks5h://127.0.0.1:9050`.
The `h` suffix is critical — it tells libcurl to send hostnames to the
SOCKS5 proxy for remote resolution through Tor. Without the `h`, DNS
queries would go through the local resolver, leaking which hosts you're
connecting to.

---

## Troubleshooting

### "Kill switch: Mullvad is not connected"

The anonymization chain must be active before stealth-fetch can send requests.

```bash
mullvad status           # Check connection
sudo mullvad connect     # Reconnect if needed
```

### "No bypass tiers available"

Dependencies not installed:

```bash
sudo ./scripts/install-stealth-deps.sh
```

### Tier 1 blocked, Tier 2 not installed

For sites with JavaScript challenges, you need Tier 2:

```bash
sudo ./scripts/install-stealth-deps.sh  # Select "yes" for Patchright
```

### "Tier 2 error: Browser not found"

Chromium binary not downloaded:

```bash
source /opt/kali-anon-chain/venv/bin/activate
python -m patchright install chromium
```

### Still blocked after both tiers

Some possibilities:
- The Mullvad exit IP is blacklisted — try `sudo mullvad reconnect` for a new relay
- The site has advanced behavioral detection — try adding `--timeout 60` for slower page loads
- Rate limiting — ensure `--no-rate-limit` is NOT set
- Try a different browser profile: `--browser safari`
