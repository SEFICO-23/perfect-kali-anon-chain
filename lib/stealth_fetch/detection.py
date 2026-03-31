"""BlockDetector — Scored multi-signal bot block detection.

Anti-bot systems don't always return 403. Amazon returns 200 with a CAPTCHA
page. Cloudflare adds challenge headers to 200 responses. Akamai serves
JavaScript redirects. This module scores responses across multiple signals
to detect blocks that simple status code checks miss.
"""

from dataclasses import dataclass
from typing import Dict, Optional
import re


@dataclass
class BlockResult:
    """Result of block detection analysis."""

    score: float           # 0.0 = clean, 1.0 = definitely blocked
    blocked: bool          # score >= threshold
    provider: str          # detected provider: cloudflare, akamai, amazon, etc.
    reason: str            # human-readable explanation
    challenge_type: str    # none, js_challenge, captcha, turnstile, redirect

    def __str__(self) -> str:
        status = "BLOCKED" if self.blocked else "CLEAN"
        return f"[{status}] score={self.score:.2f} provider={self.provider} reason={self.reason}"


# Detection threshold — scores at or above this are considered blocked
DEFAULT_THRESHOLD = 0.5


def detect(
    status_code: int,
    body: str,
    headers: Dict[str, str],
    expected_min_size: int = 5000,
    threshold: float = DEFAULT_THRESHOLD,
) -> BlockResult:
    """Analyze a response for bot block signals. Returns a BlockResult."""

    score = 0.0
    provider = "unknown"
    reasons = []
    challenge_type = "none"

    body_lower = body.lower() if body else ""
    body_len = len(body) if body else 0

    # Normalize headers to lowercase keys
    h = {k.lower(): v for k, v in headers.items()} if headers else {}

    # ── HTTP status signals ──────────────────────────────────────────────
    if status_code == 403:
        score += 0.6
        reasons.append(f"HTTP {status_code}")
    elif status_code == 429:
        score += 0.7
        reasons.append("rate limited (429)")
    elif status_code == 503:
        score += 0.3
        reasons.append(f"HTTP {status_code}")

    # ── Cloudflare signals ───────────────────────────────────────────────
    if h.get("server", "").lower() == "cloudflare":
        if "cf-mitigated" in h:
            score += 0.7
            provider = "cloudflare"
            reasons.append("cf-mitigated header present")
            challenge_type = "js_challenge"

        if "challenges.cloudflare.com" in body_lower:
            score += 0.6
            provider = "cloudflare"
            reasons.append("Cloudflare challenge page")
            challenge_type = "turnstile"

        if "checking if the site connection is secure" in body_lower:
            score += 0.5
            provider = "cloudflare"
            reasons.append("Cloudflare security check text")
            challenge_type = "js_challenge"

        if "just a moment" in body_lower and status_code == 503:
            score += 0.6
            provider = "cloudflare"
            reasons.append("Cloudflare 'Just a moment' page")
            challenge_type = "js_challenge"

    # Check for Cloudflare cookies without clearance
    set_cookie = h.get("set-cookie", "")
    if "__cf_bm" in set_cookie and "cf_clearance" not in set_cookie:
        score += 0.2
        if provider == "unknown":
            provider = "cloudflare"
        reasons.append("__cf_bm cookie without cf_clearance")

    # ── AWS WAF signals ─────────────────────────────────────────────────
    if h.get("x-amzn-waf-action", "") == "challenge":
        score += 0.7
        provider = "aws_waf"
        reasons.append("AWS WAF challenge header (x-amzn-waf-action: challenge)")
        challenge_type = "js_challenge"

    if "awswaf.com" in body_lower and "challenge.js" in body_lower:
        score += 0.5
        if provider == "unknown":
            provider = "aws_waf"
        reasons.append("AWS WAF challenge.js script")
        challenge_type = "js_challenge"

    if status_code == 202 and body_len < 3000:
        if "awswafintegration" in body_lower or "challenge-container" in body_lower:
            score += 0.4
            if provider == "unknown":
                provider = "aws_waf"
            reasons.append("HTTP 202 with WAF challenge container")
            challenge_type = "js_challenge"

    # ── Amazon signals ───────────────────────────────────────────────────
    if "/errors/validatecaptcha" in body_lower:
        score += 0.8
        provider = "amazon"
        reasons.append("Amazon CAPTCHA validation form")
        challenge_type = "captcha"

    if "sorry, we just need to make sure you're not a robot" in body_lower:
        score += 0.7
        provider = "amazon"
        reasons.append("Amazon robot check text")
        challenge_type = "captcha"

    if "to discuss automated access to amazon data" in body_lower:
        score += 0.6
        provider = "amazon"
        reasons.append("Amazon automated access warning")
        challenge_type = "captcha"

    # ── Akamai signals ───────────────────────────────────────────────────
    if h.get("server", "").lower() in ("akamaighost", "akamai"):
        if body_len < expected_min_size and body_len > 0:
            score += 0.4
            provider = "akamai"
            reasons.append(f"Akamai with small body ({body_len} bytes)")

    if "_abck" in set_cookie:
        # _abck cookie without proper JS execution = sensor challenge
        score += 0.3
        if provider == "unknown":
            provider = "akamai"
        reasons.append("Akamai _abck cookie (sensor challenge)")
        challenge_type = "js_challenge"

    # ── PerimeterX / HUMAN signals ───────────────────────────────────────
    if '<div id="px-captcha">' in body_lower or "px-captcha" in body_lower:
        score += 0.7
        provider = "perimeterx"
        reasons.append("PerimeterX CAPTCHA div")
        challenge_type = "captcha"

    if "_px3" in set_cookie or "_pxhd" in set_cookie:
        score += 0.3
        if provider == "unknown":
            provider = "perimeterx"
        reasons.append("PerimeterX cookies")

    # ── DataDome signals ─────────────────────────────────────────────────
    if "x-datadome" in h:
        score += 0.3
        provider = "datadome"
        reasons.append("DataDome header")

    if "geo.captcha-delivery.com" in body_lower:
        score += 0.6
        provider = "datadome"
        reasons.append("DataDome CAPTCHA delivery script")
        challenge_type = "captcha"

    # ── Generic signals ──────────────────────────────────────────────────
    # Suspiciously small body for a page that should be larger
    if body_len > 0 and body_len < 2000 and expected_min_size > 5000:
        score += 0.2
        reasons.append(f"Body suspiciously small ({body_len} < 2000 bytes)")

    # Empty body with only script tags (JS-only challenge page)
    if body and re.search(r"<body[^>]*>\s*<script", body_lower):
        visible_text = re.sub(r"<[^>]+>", "", body)
        if len(visible_text.strip()) < 100:
            score += 0.4
            reasons.append("JS-only page (no visible content)")
            if challenge_type == "none":
                challenge_type = "js_challenge"

    # ── Clamp and decide ─────────────────────────────────────────────────
    score = min(score, 1.0)
    blocked = score >= threshold

    reason_str = "; ".join(reasons) if reasons else "no block signals detected"

    return BlockResult(
        score=score,
        blocked=blocked,
        provider=provider,
        reason=reason_str,
        challenge_type=challenge_type,
    )
