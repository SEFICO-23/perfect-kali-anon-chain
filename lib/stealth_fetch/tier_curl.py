"""Tier 1: curl-cffi — TLS/JA3 fingerprint spoofing.

Fast, lightweight (~20MB), no browser engine needed.
Spoofs Chrome/Safari TLS fingerprints at the C library level.
Handles HTTP/2 fingerprinting automatically.

Limitations:
- Cannot execute JavaScript (no challenge solving)
- Cannot handle Cloudflare Turnstile or Akamai sensor challenges
"""

from typing import Dict, Optional, Tuple
import sys

from .profiles import BrowserProfile


def available() -> bool:
    """Check if curl-cffi is installed."""
    try:
        from curl_cffi import requests  # noqa: F401
        return True
    except ImportError:
        return False


def fetch(
    url: str,
    profile: BrowserProfile,
    cookies: Optional[Dict[str, str]] = None,
    proxy: Optional[str] = None,
    interface: Optional[str] = None,
    timeout: int = 30,
    custom_headers: Optional[Dict[str, str]] = None,
) -> Tuple[int, str, Dict[str, str], list]:
    """Fetch a URL with TLS fingerprint impersonation.

    Args:
        url: The URL to fetch.
        profile: BrowserProfile with impersonation target and headers.
        cookies: Dict of cookies to send.
        proxy: Proxy URL (e.g., socks5h://127.0.0.1:9050).
        interface: Network interface to bind to (e.g., wg0-mullvad).
        timeout: Request timeout in seconds.
        custom_headers: Additional headers to merge with profile headers.

    Returns:
        Tuple of (status_code, body, response_headers, set_cookie_list).
    """
    from curl_cffi import requests

    headers = profile.headers(custom_headers)

    kwargs = {
        "url": url,
        "impersonate": profile.impersonate,
        "headers": headers,
        "timeout": timeout,
        "allow_redirects": True,
        "max_redirects": 5,
    }

    if cookies:
        kwargs["cookies"] = cookies

    if proxy:
        kwargs["proxies"] = {"https": proxy, "http": proxy}

    if interface:
        kwargs["interface"] = interface

    resp = requests.get(**kwargs)

    # Extract Set-Cookie headers for session management
    set_cookies = []
    if hasattr(resp, "headers"):
        # curl-cffi returns headers as a special object
        for key, value in resp.headers.items():
            if key.lower() == "set-cookie":
                set_cookies.append(value)

    resp_headers = dict(resp.headers) if hasattr(resp, "headers") else {}

    return resp.status_code, resp.text, resp_headers, set_cookies
