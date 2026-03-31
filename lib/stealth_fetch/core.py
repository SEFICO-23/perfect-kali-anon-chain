"""StealthFetch — Orchestrator for tiered anti-bot bypass.

Manages the escalation flow:
  KillSwitch → RateLimiter → Tier1(curl-cffi) → BlockDetector
  → if blocked → Tier2(Patchright) → BlockDetector → return
"""

import sys
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from . import detection, killswitch
from .profiles import BrowserProfile, get_profile
from .session import SessionManager
from .ratelimit import RateLimiter
from . import tier_curl, tier_browser


@dataclass
class FetchResult:
    """Result of a stealth-fetch request."""

    url: str
    status_code: int
    body: str
    headers: Dict[str, str]
    tier_used: str               # "tier1", "tier2", or "none"
    block_result: detection.BlockResult
    tiers_attempted: List[str] = field(default_factory=list)
    elapsed_seconds: float = 0.0
    error: Optional[str] = None


class StealthFetch:
    """Main orchestrator for anti-bot bypass requests."""

    def __init__(
        self,
        profile_name: str = "chrome",
        proxy: Optional[str] = None,
        no_kill_switch: bool = False,
        rate_limit: bool = True,
        min_delay: float = 1.5,
        max_delay: float = 4.5,
        session_dir: Optional[str] = None,
        verbose: bool = False,
    ):
        self.profile = get_profile(profile_name)
        self.proxy = proxy
        self.no_kill_switch = no_kill_switch
        self.verbose = verbose
        self.session = SessionManager(persist_dir=session_dir)
        self.rate_limiter = RateLimiter(
            min_delay=min_delay,
            max_delay=max_delay,
            enabled=rate_limit,
        )

        # Determine available tiers at init
        self.tier1_available = tier_curl.available()
        self.tier2_available = tier_browser.available()

        if verbose:
            self._log(f"Profile: {self.profile.name}")
            self._log(f"Tier 1 (curl-cffi): {'available' if self.tier1_available else 'NOT installed'}")
            self._log(f"Tier 2 (Patchright): {'available' if self.tier2_available else 'NOT installed'}")

    def _log(self, msg: str) -> None:
        """Print verbose log message to stderr."""
        if self.verbose:
            print(f"[stealth-fetch] {msg}", file=sys.stderr)

    def _get_interface(self) -> Optional[str]:
        """Get the Mullvad WireGuard interface name for binding."""
        if self.no_kill_switch:
            return None
        try:
            result = killswitch.verify(skip=False)
            return result.get("mullvad_interface")
        except killswitch.NetworkLeakError:
            return None

    def fetch(
        self,
        url: str,
        tier: str = "auto",
        custom_headers: Optional[Dict[str, str]] = None,
        timeout: int = 30,
    ) -> FetchResult:
        """Fetch a URL with anti-bot bypass.

        Args:
            url: URL to fetch.
            tier: "auto" (escalate), "1" (curl-cffi only), "2" (Patchright only).
            custom_headers: Extra headers to add to the profile's header set.
            timeout: Request timeout in seconds.

        Returns:
            FetchResult with body, status, tier used, and block analysis.
        """
        start_time = time.time()
        tiers_attempted = []

        # ── Kill switch check ────────────────────────────────────────────
        if not self.no_kill_switch:
            self._log("Verifying anonymization chain...")
            try:
                ks_result = killswitch.verify(skip=False)
                self._log(f"Chain OK: Mullvad connected, interface={ks_result['mullvad_interface']}")
            except killswitch.NetworkLeakError as e:
                return FetchResult(
                    url=url,
                    status_code=0,
                    body="",
                    headers={},
                    tier_used="none",
                    block_result=detection.BlockResult(
                        score=0, blocked=False, provider="", reason="", challenge_type="none"
                    ),
                    tiers_attempted=[],
                    elapsed_seconds=time.time() - start_time,
                    error=f"Kill switch: {e}",
                )

        # ── Rate limiting ────────────────────────────────────────────────
        waited = self.rate_limiter.wait(url)
        if waited > 0:
            self._log(f"Rate limited: waited {waited:.1f}s")

        # Get interface for binding (Tier 1 only)
        interface = self._get_interface() if not self.proxy else None

        # Get cookies for this domain
        cookies = self.session.get_cookies_dict(url)

        # ── Tier dispatch ────────────────────────────────────────────────
        if tier == "1" or (tier == "auto" and self.tier1_available):
            result = self._try_tier1(url, cookies, interface, timeout, custom_headers)
            tiers_attempted.append("tier1")

            if result and (tier == "1" or not result.block_result.blocked):
                result.tiers_attempted = tiers_attempted
                result.elapsed_seconds = time.time() - start_time
                return result

            if tier == "1":
                # Forced tier 1 — return even if blocked
                result.tiers_attempted = tiers_attempted
                result.elapsed_seconds = time.time() - start_time
                return result

            # Auto mode — escalate to tier 2
            self._log(f"Tier 1 blocked: {result.block_result}")
            cookies = self.session.get_cookies_dict(url)  # May have new cookies

        if tier == "2" or (tier == "auto" and self.tier2_available):
            result = self._try_tier2(url, cookies, timeout, custom_headers)
            tiers_attempted.append("tier2")

            if result:
                result.tiers_attempted = tiers_attempted
                result.elapsed_seconds = time.time() - start_time
                return result

        # ── All tiers failed or none available ───────────────────────────
        elapsed = time.time() - start_time
        error_msg = "No bypass tiers available" if not tiers_attempted else "All tiers failed"
        if not self.tier1_available and not self.tier2_available:
            error_msg += ". Run: sudo ./scripts/install-stealth-deps.sh"

        return FetchResult(
            url=url,
            status_code=0,
            body="",
            headers={},
            tier_used="none",
            block_result=detection.BlockResult(
                score=0, blocked=False, provider="", reason="", challenge_type="none"
            ),
            tiers_attempted=tiers_attempted,
            elapsed_seconds=elapsed,
            error=error_msg,
        )

    def _try_tier1(
        self, url: str, cookies: Dict, interface: Optional[str],
        timeout: int, custom_headers: Optional[Dict],
    ) -> Optional[FetchResult]:
        """Attempt Tier 1 (curl-cffi)."""
        if not self.tier1_available:
            self._log("Tier 1 skipped (curl-cffi not installed)")
            return None

        self._log("Trying Tier 1 (curl-cffi)...")

        try:
            status, body, headers, set_cookies = tier_curl.fetch(
                url=url,
                profile=self.profile,
                cookies=cookies if cookies else None,
                proxy=self.proxy,
                interface=interface,
                timeout=timeout,
                custom_headers=custom_headers,
            )

            # Update session cookies
            if set_cookies:
                self.session.set_cookies_from_headers(url, set_cookies)

            block = detection.detect(status, body, headers)
            self._log(f"Tier 1 result: HTTP {status}, {block}")

            return FetchResult(
                url=url, status_code=status, body=body, headers=headers,
                tier_used="tier1", block_result=block,
            )

        except Exception as e:
            self._log(f"Tier 1 error: {e}")
            return FetchResult(
                url=url, status_code=0, body="", headers={},
                tier_used="tier1",
                block_result=detection.BlockResult(
                    score=0, blocked=False, provider="", reason="", challenge_type="none"
                ),
                error=str(e),
            )

    def _try_tier2(
        self, url: str, cookies: Dict,
        timeout: int, custom_headers: Optional[Dict],
    ) -> Optional[FetchResult]:
        """Attempt Tier 2 (Patchright)."""
        if not self.tier2_available:
            self._log("Tier 2 skipped (Patchright not installed)")
            return None

        self._log("Trying Tier 2 (Patchright headless browser)...")

        try:
            status, body, headers, set_cookies = tier_browser.fetch(
                url=url,
                user_agent=self.profile.user_agent,
                cookies=cookies if cookies else None,
                proxy=self.proxy,
                timeout=timeout,
                custom_headers=custom_headers,
            )

            # Update session cookies
            if set_cookies:
                self.session.set_cookies_from_headers(url, set_cookies)

            block = detection.detect(status, body, headers)
            self._log(f"Tier 2 result: HTTP {status}, {block}")

            return FetchResult(
                url=url, status_code=status, body=body, headers=headers,
                tier_used="tier2", block_result=block,
            )

        except Exception as e:
            self._log(f"Tier 2 error: {e}")
            return FetchResult(
                url=url, status_code=0, body="", headers={},
                tier_used="tier2",
                block_result=detection.BlockResult(
                    score=0, blocked=False, provider="", reason="", challenge_type="none"
                ),
                error=str(e),
            )
