"""BrowserProfile — Consistent fingerprint bundles.

Bundles TLS impersonation target, User-Agent, Sec-Ch-Ua, and all
correlated HTTP headers into a single object. This prevents mismatches
between TLS fingerprint and HTTP headers, which anti-bot systems detect.

curl-cffi only supports Chrome/Safari/Edge (BoringSSL-based). Firefox
uses NSS and is NOT supported — never send a Firefox User-Agent with
curl-cffi or the TLS/header mismatch will be detected immediately.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional


@dataclass(frozen=True)
class BrowserProfile:
    """Immutable bundle of correlated browser fingerprint artifacts."""

    name: str
    impersonate: str              # curl-cffi impersonation target
    user_agent: str
    sec_ch_ua: str
    sec_ch_ua_platform: str
    sec_ch_ua_mobile: str
    accept: str
    accept_language: str
    accept_encoding: str
    extra_headers: Dict[str, str] = field(default_factory=dict)

    def headers(self, custom: Optional[Dict[str, str]] = None) -> Dict[str, str]:
        """Generate full header dict in Chrome's header order.

        Chrome sends headers in a specific order. Akamai checks this.
        The order below matches Chrome 120+ on Windows/Linux.
        """
        h = {}
        # Chrome header order (observed via Wireshark/DevTools):
        h["Host"] = ""  # Will be set by the HTTP library from the URL
        h["Cache-Control"] = "max-age=0"
        h["Sec-Ch-Ua"] = self.sec_ch_ua
        h["Sec-Ch-Ua-Mobile"] = self.sec_ch_ua_mobile
        h["Sec-Ch-Ua-Platform"] = self.sec_ch_ua_platform
        h["Upgrade-Insecure-Requests"] = "1"
        h["User-Agent"] = self.user_agent
        h["Accept"] = self.accept
        h["Sec-Fetch-Site"] = "none"
        h["Sec-Fetch-Mode"] = "navigate"
        h["Sec-Fetch-User"] = "?1"
        h["Sec-Fetch-Dest"] = "document"
        h["Accept-Encoding"] = self.accept_encoding
        h["Accept-Language"] = self.accept_language

        # Add profile-specific extras
        h.update(self.extra_headers)

        # Apply custom overrides last
        if custom:
            h.update(custom)

        # Remove the placeholder Host header (library sets it from URL)
        h.pop("Host", None)

        return h


# ── Profile Registry ─────────────────────────────────────────────────────────
# Each profile matches a real Chrome version's exact fingerprint artifacts.
# Update these when new Chrome versions become the dominant browser.

PROFILES: Dict[str, BrowserProfile] = {}


def _register(p: BrowserProfile) -> None:
    PROFILES[p.name] = p


_register(BrowserProfile(
    name="chrome",
    impersonate="chrome",  # curl-cffi auto-latest
    user_agent=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/131.0.0.0 Safari/537.36"
    ),
    sec_ch_ua='"Chromium";v="131", "Google Chrome";v="131", "Not_A Brand";v="24"',
    sec_ch_ua_platform='"Windows"',
    sec_ch_ua_mobile="?0",
    accept=(
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,image/apng,*/*;q=0.8,"
        "application/signed-exchange;v=b3;q=0.7"
    ),
    accept_language="en-US,en;q=0.9",
    accept_encoding="gzip, deflate, br, zstd",
))

_register(BrowserProfile(
    name="chrome131",
    impersonate="chrome131",
    user_agent=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/131.0.0.0 Safari/537.36"
    ),
    sec_ch_ua='"Chromium";v="131", "Google Chrome";v="131", "Not_A Brand";v="24"',
    sec_ch_ua_platform='"Windows"',
    sec_ch_ua_mobile="?0",
    accept=(
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,image/apng,*/*;q=0.8,"
        "application/signed-exchange;v=b3;q=0.7"
    ),
    accept_language="en-US,en;q=0.9",
    accept_encoding="gzip, deflate, br, zstd",
))

_register(BrowserProfile(
    name="chrome136",
    impersonate="chrome136",
    user_agent=(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/136.0.0.0 Safari/537.36"
    ),
    sec_ch_ua='"Chromium";v="136", "Google Chrome";v="136", "Not_A Brand";v="99"',
    sec_ch_ua_platform='"Windows"',
    sec_ch_ua_mobile="?0",
    accept=(
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,image/apng,*/*;q=0.8,"
        "application/signed-exchange;v=b3;q=0.7"
    ),
    accept_language="en-US,en;q=0.9",
    accept_encoding="gzip, deflate, br, zstd",
))

_register(BrowserProfile(
    name="safari",
    impersonate="safari17_0",
    user_agent=(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) "
        "Version/17.0 Safari/605.1.15"
    ),
    sec_ch_ua="",  # Safari doesn't send Sec-Ch-Ua
    sec_ch_ua_platform="",
    sec_ch_ua_mobile="",
    accept="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    accept_language="en-US,en;q=0.9",
    accept_encoding="gzip, deflate, br",
))


def get_profile(name: str = "chrome") -> BrowserProfile:
    """Get a browser profile by name. Defaults to auto-latest Chrome."""
    if name not in PROFILES:
        available = ", ".join(sorted(PROFILES.keys()))
        raise ValueError(f"Unknown profile '{name}'. Available: {available}")
    return PROFILES[name]


def list_profiles() -> List[str]:
    """List all available profile names."""
    return sorted(PROFILES.keys())
