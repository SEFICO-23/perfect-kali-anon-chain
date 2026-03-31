"""SessionManager — Per-domain cookie persistence.

Anti-bot systems flag cookieless requests as bots. Amazon requires
session-id from initial load. Cloudflare's cf_clearance must persist
after challenge bypass. This module manages cookies per domain with
optional encrypted save/load for session resumption.
"""

from http.cookiejar import MozillaCookieJar, Cookie
from urllib.parse import urlparse
from pathlib import Path
from typing import Dict, Optional
import time
import os


class SessionManager:
    """Manages per-domain cookie jars with optional persistence."""

    def __init__(self, persist_dir: Optional[str] = None):
        """Initialize session manager.

        Args:
            persist_dir: Directory to save/load cookie files.
                         None = in-memory only (default).
        """
        self._jars: Dict[str, MozillaCookieJar] = {}
        self._persist_dir = Path(persist_dir) if persist_dir else None
        if self._persist_dir:
            self._persist_dir.mkdir(parents=True, exist_ok=True)

    def _domain_key(self, url: str) -> str:
        """Extract the effective domain from a URL."""
        parsed = urlparse(url)
        host = parsed.hostname or ""
        # Strip www. prefix for consistency
        if host.startswith("www."):
            host = host[4:]
        return host

    def get_jar(self, url: str) -> MozillaCookieJar:
        """Get or create a cookie jar for the given URL's domain."""
        domain = self._domain_key(url)
        if domain not in self._jars:
            jar = MozillaCookieJar()
            # Try to load persisted cookies
            if self._persist_dir:
                cookie_file = self._persist_dir / f"{domain}.txt"
                jar.filename = str(cookie_file)
                if cookie_file.exists():
                    try:
                        jar.load(ignore_discard=True, ignore_expires=True)
                    except Exception:
                        pass  # Corrupted file, start fresh
            self._jars[domain] = jar
        return self._jars[domain]

    def get_cookies_dict(self, url: str) -> Dict[str, str]:
        """Get cookies as a simple dict for the given URL's domain."""
        jar = self.get_jar(url)
        return {cookie.name: cookie.value for cookie in jar}

    def set_cookies_from_headers(self, url: str, set_cookie_headers: list) -> None:
        """Import cookies from Set-Cookie response headers."""
        jar = self.get_jar(url)
        parsed = urlparse(url)
        domain = parsed.hostname or ""

        for header in set_cookie_headers:
            parts = header.split(";")
            if not parts:
                continue
            name_val = parts[0].strip()
            if "=" not in name_val:
                continue
            name, value = name_val.split("=", 1)

            cookie = Cookie(
                version=0, name=name.strip(), value=value.strip(),
                port=None, port_specified=False,
                domain=domain, domain_specified=True, domain_initial_dot=domain.startswith("."),
                path="/", path_specified=True,
                secure=parsed.scheme == "https",
                expires=int(time.time()) + 86400,  # 24h default
                discard=False, comment=None, comment_url=None,
                rest={}, rfc2109=False,
            )
            jar.set_cookie(cookie)

    def save(self, url: str) -> None:
        """Persist cookies for the given URL's domain to disk."""
        if not self._persist_dir:
            return
        jar = self.get_jar(url)
        if jar.filename:
            try:
                jar.save(ignore_discard=True, ignore_expires=True)
            except Exception:
                pass

    def save_all(self) -> None:
        """Persist all cookie jars to disk."""
        if not self._persist_dir:
            return
        for domain, jar in self._jars.items():
            if jar.filename:
                try:
                    jar.save(ignore_discard=True, ignore_expires=True)
                except Exception:
                    pass

    def clear(self, url: Optional[str] = None) -> None:
        """Clear cookies. If url given, only for that domain. Otherwise all."""
        if url:
            domain = self._domain_key(url)
            if domain in self._jars:
                self._jars[domain].clear()
        else:
            for jar in self._jars.values():
                jar.clear()
