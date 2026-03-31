"""Tier 2: Patchright — Compile-time patched headless Chromium.

Patchright is a fork of Playwright that patches the Chromium binary itself
to remove automation signals. Unlike playwright-stealth (which only patches
JavaScript), Patchright modifies the browser at the C++ level, making it
much harder for anti-bot systems to detect.

Same API as Playwright — drop-in replacement.

Handles:
- JavaScript challenges (Cloudflare Turnstile, Akamai sensor)
- Full DOM rendering for SPAs
- Cookie management with browser-level jar
"""

from typing import Dict, Optional, Tuple
import sys


def available() -> bool:
    """Check if Patchright is installed."""
    try:
        from patchright.sync_api import sync_playwright  # noqa: F401
        return True
    except ImportError:
        return False


def fetch(
    url: str,
    user_agent: str,
    cookies: Optional[Dict[str, str]] = None,
    proxy: Optional[str] = None,
    timeout: int = 30,
    custom_headers: Optional[Dict[str, str]] = None,
    wait_until: str = "domcontentloaded",
) -> Tuple[int, str, Dict[str, str], list]:
    """Fetch a URL with a full headless browser.

    Args:
        url: The URL to fetch.
        user_agent: User-Agent string (should match the BrowserProfile).
        cookies: Dict of cookies to inject before navigation.
        proxy: Proxy URL (e.g., socks5://127.0.0.1:9050).
        timeout: Page load timeout in seconds.
        custom_headers: Extra HTTP headers to set.
        wait_until: Playwright wait condition (domcontentloaded, networkidle, load).

    Returns:
        Tuple of (status_code, body, response_headers, set_cookie_list).
    """
    from patchright.sync_api import sync_playwright

    # Use headless=False + --headless=new to launch FULL Chromium in headless
    # mode. headless=True uses chrome-headless-shell which is trivially
    # detected by anti-bot systems. The "new headless" mode runs the real
    # browser without a visible window — same JS engine, same fingerprint.
    launch_opts = {
        "headless": False,
        "args": [
            "--headless=new",
            "--no-sandbox",
            "--disable-blink-features=AutomationControlled",
        ],
    }
    if proxy:
        launch_opts["proxy"] = {"server": proxy}

    status_code = 0
    body = ""
    resp_headers = {}
    set_cookies = []

    with sync_playwright() as p:
        browser = p.chromium.launch(**launch_opts)

        context_opts = {
            "user_agent": user_agent,
            "locale": "en-US",
            "timezone_id": "America/New_York",
            "viewport": {"width": 1920, "height": 1080},
            "screen": {"width": 1920, "height": 1080},
            "color_scheme": "light",
            "java_script_enabled": True,
        }

        context = browser.new_context(**context_opts)

        # Inject cookies before navigation
        if cookies:
            from urllib.parse import urlparse
            parsed = urlparse(url)
            domain = parsed.hostname or ""
            cookie_list = [
                {
                    "name": name,
                    "value": value,
                    "domain": domain,
                    "path": "/",
                    "httpOnly": False,
                    "secure": parsed.scheme == "https",
                }
                for name, value in cookies.items()
            ]
            context.add_cookies(cookie_list)

        page = context.new_page()

        # Set extra headers if provided
        if custom_headers:
            page.set_extra_http_headers(custom_headers)

        try:
            response = page.goto(
                url,
                wait_until=wait_until,
                timeout=timeout * 1000,
            )

            if response:
                status_code = response.status
                resp_headers = response.all_headers()

            # Wait for post-load JS to settle (initial)
            page.wait_for_timeout(2000)

            # Check for anti-bot challenge pages that auto-resolve via JS.
            # Amazon's opfcaptcha, Cloudflare's cf-challenge, and similar
            # systems serve a JS challenge that redirects after solving.
            # We detect these and wait for the redirect to complete.
            initial_body = page.content()
            challenge_markers = [
                "opfcaptcha",       # Amazon silent captcha
                "cf-challenge",     # Cloudflare challenge
                "challenge-form",   # Generic challenge
                "jschl-answer",     # Cloudflare legacy
                "_cf_chl_opt",      # Cloudflare managed
            ]
            if any(m in initial_body.lower() for m in challenge_markers):
                # Challenge detected — wait for JS to solve and redirect
                try:
                    page.wait_for_url(
                        lambda u: "captcha" not in u and "challenge" not in u,
                        timeout=15000,
                    )
                except Exception:
                    pass  # Timeout is OK — we'll check the body regardless

                # Additional settle time after potential redirect
                page.wait_for_timeout(3000)
                # Re-read status from current page
                body_after = page.content()
                if len(body_after) > len(initial_body):
                    initial_body = body_after

            body = initial_body if initial_body else page.content()

            # Extract cookies set during navigation
            browser_cookies = context.cookies()
            for c in browser_cookies:
                set_cookies.append(f"{c['name']}={c['value']}")

        except Exception as e:
            # Page load timeout or navigation error
            body = f"<error>{str(e)}</error>"
            status_code = 0

        finally:
            browser.close()

    return status_code, body, resp_headers, set_cookies
