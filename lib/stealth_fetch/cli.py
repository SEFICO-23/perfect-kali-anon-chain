#!/usr/bin/env python3
"""CLI entry point for stealth-fetch.

Usage:
    python -m stealth_fetch <url> [options]
    stealth-fetch <url> [options]

Examples:
    stealth-fetch https://amazon.com --tier auto -v
    stealth-fetch https://example.com --tier 1 --json
    stealth-fetch https://nowsecure.nl --tier 2 -o page.html
"""

import argparse
import json
import sys
import os

# Add lib/ to path so the package can be found
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.path.dirname(SCRIPT_DIR)
if LIB_DIR not in sys.path:
    sys.path.insert(0, LIB_DIR)

from stealth_fetch.core import StealthFetch
from stealth_fetch.profiles import list_profiles


def main():
    parser = argparse.ArgumentParser(
        description="Anti-bot bypass fetcher for the Kali Anon Chain",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Tiers:\n"
            "  1    curl-cffi — TLS/JA3 fingerprint spoofing (fast, ~20MB)\n"
            "  2    Patchright — headless Chromium with binary patches (~250MB)\n"
            "  auto Try tier 1 first, escalate to tier 2 if blocked (default)\n"
            "\n"
            "Examples:\n"
            "  %(prog)s https://amazon.com --tier auto -v\n"
            "  %(prog)s https://httpbin.org/user-agent --tier 1 --json\n"
            "  %(prog)s https://nowsecure.nl --tier 2 -o page.html\n"
        ),
    )

    parser.add_argument("url", help="URL to fetch")
    parser.add_argument(
        "--tier", default="auto", choices=["auto", "1", "2"],
        help="Bypass tier (default: auto = try tier 1, escalate if blocked)",
    )
    parser.add_argument(
        "--tor-direct", action="store_true",
        help="Route through raw Tor SOCKS5 (socks5h://127.0.0.1:9050) instead of Mullvad",
    )
    parser.add_argument(
        "--browser", default="chrome", choices=list_profiles(),
        help=f"Impersonation profile (default: chrome). Available: {', '.join(list_profiles())}",
    )
    parser.add_argument(
        "--header", action="append", default=[], metavar="KEY:VAL",
        help="Add custom HTTP header (repeatable)",
    )
    parser.add_argument(
        "--timeout", type=int, default=30,
        help="Request timeout in seconds (default: 30)",
    )
    parser.add_argument(
        "-o", "--output", metavar="FILE",
        help="Write HTML body to file instead of stdout",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="JSON output with metadata (tier, status, block score, headers)",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Show tier attempts, timings, and diagnostics on stderr",
    )
    parser.add_argument(
        "--no-kill-switch", action="store_true",
        help="Disable Mullvad connection check (UNSAFE — for testing only)",
    )
    parser.add_argument(
        "--no-rate-limit", action="store_true",
        help="Disable per-domain rate limiting",
    )

    args = parser.parse_args()

    # Parse custom headers
    custom_headers = {}
    for h in args.header:
        if ":" not in h:
            print(f"Invalid header format: '{h}' (expected KEY:VALUE)", file=sys.stderr)
            sys.exit(1)
        key, val = h.split(":", 1)
        custom_headers[key.strip()] = val.strip()

    # Determine proxy
    proxy = None
    if args.tor_direct:
        proxy = "socks5h://127.0.0.1:9050"

    # Create fetcher
    fetcher = StealthFetch(
        profile_name=args.browser,
        proxy=proxy,
        no_kill_switch=args.no_kill_switch,
        rate_limit=not args.no_rate_limit,
        verbose=args.verbose,
    )

    # Fetch
    result = fetcher.fetch(
        url=args.url,
        tier=args.tier,
        custom_headers=custom_headers if custom_headers else None,
        timeout=args.timeout,
    )

    # Handle errors
    if result.error:
        print(f"Error: {result.error}", file=sys.stderr)
        if not result.body and not args.json:
            sys.exit(1)

    # Output
    if args.json:
        output = {
            "url": result.url,
            "status_code": result.status_code,
            "tier_used": result.tier_used,
            "tiers_attempted": result.tiers_attempted,
            "elapsed_seconds": round(result.elapsed_seconds, 2),
            "block_score": result.block_result.score,
            "block_provider": result.block_result.provider,
            "block_reason": result.block_result.reason,
            "blocked": result.block_result.blocked,
            "error": result.error,
            "body_length": len(result.body),
            "body_preview": result.body[:500] if result.body else "",
        }
        print(json.dumps(output, indent=2))
    elif args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(result.body)
        if args.verbose:
            print(f"Written to {args.output} ({len(result.body)} bytes)", file=sys.stderr)
    else:
        print(result.body)

    # Exit code: 0 if successful, 1 if blocked/error
    if result.error or result.block_result.blocked:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
