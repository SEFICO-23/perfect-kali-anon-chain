"""RateLimiter — Per-domain randomized request delays.

Even with perfect fingerprinting, rapid requests from one IP get flagged.
Fixed intervals (e.g., exactly 2s between requests) are themselves a bot
signature. This module uses randomized delays with jitter.
"""

import time
import random
from typing import Dict, Optional


class RateLimiter:
    """Enforces per-domain minimum delays with random jitter."""

    def __init__(
        self,
        min_delay: float = 1.5,
        max_delay: float = 4.5,
        enabled: bool = True,
    ):
        """Initialize rate limiter.

        Args:
            min_delay: Minimum seconds between requests to same domain.
            max_delay: Maximum seconds between requests to same domain.
            enabled: If False, no delays are applied.
        """
        self.min_delay = min_delay
        self.max_delay = max_delay
        self.enabled = enabled
        self._last_request: Dict[str, float] = {}

    def _domain_key(self, url: str) -> str:
        """Extract domain from URL for rate tracking."""
        from urllib.parse import urlparse
        parsed = urlparse(url)
        host = parsed.hostname or ""
        if host.startswith("www."):
            host = host[4:]
        return host

    def wait(self, url: str) -> float:
        """Wait if needed before making a request to the URL's domain.

        Returns:
            The number of seconds actually waited (0 if no wait needed).
        """
        if not self.enabled:
            return 0.0

        domain = self._domain_key(url)
        now = time.time()
        last = self._last_request.get(domain, 0)
        elapsed = now - last

        # Calculate required delay with jitter
        required_delay = random.uniform(self.min_delay, self.max_delay)

        if elapsed < required_delay:
            wait_time = required_delay - elapsed
            time.sleep(wait_time)
            self._last_request[domain] = time.time()
            return wait_time

        self._last_request[domain] = now
        return 0.0

    def reset(self, url: Optional[str] = None) -> None:
        """Reset rate tracking. If url given, only for that domain."""
        if url:
            domain = self._domain_key(url)
            self._last_request.pop(domain, None)
        else:
            self._last_request.clear()
