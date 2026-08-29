"""Capture REAL submission screenshots from live PLX App / toolkit (900x1600)."""
from __future__ import annotations

from pathlib import Path

from playwright.sync_api import Page, sync_playwright

OUT = Path(r"D:\DATA TOOLS\PLX-ACTON\metadata\app-submission")

TG_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 "
    "Telegram-iOS/10.0"
)

INIT_SCRIPT = """
try {
  sessionStorage.setItem('plx_event_popup_dismissed', '1');
  localStorage.setItem('plx_event_popup_dismissed_at', String(Date.now()));
} catch (e) {}
"""


def prep(page: Page, url: str) -> None:
    try:
        page.goto(url, wait_until="networkidle", timeout=70000)
    except Exception as exc:
        print("goto warn", exc)
        page.goto(url, wait_until="domcontentloaded", timeout=45000)
    page.wait_for_timeout(2500)
    try:
        btn = page.locator("button.event-popup-close").first
        if btn.is_visible(timeout=800):
            btn.click()
            page.wait_for_timeout(700)
    except Exception:
        pass


def capture(page: Page, name: str) -> None:
    path = OUT / name
    page.screenshot(path=str(path), full_page=False)
    print("SAVED", path, path.stat().st_size)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, channel="chrome")
        context = browser.new_context(
            viewport={"width": 900, "height": 1600},
            device_scale_factor=1,
            user_agent=TG_UA,
            is_mobile=True,
            has_touch=True,
        )
        page = context.new_page()
        page.add_init_script(INIT_SCRIPT)

        # 1) Mini App — Formation / Earn (real app shell)
        prep(page, "https://app.plx.foundation/earn")
        capture(page, "screenshot-01-plx-app.png")

        # 2) PLX Token page — live reference + on-chain context (real toolkit UI)
        prep(page, "https://plx.foundation/plx-token")
        page.wait_for_timeout(1200)
        capture(page, "screenshot-02-dashboard.png")

        # 3) Build wizard on homepage (real deploy UI — customize + live preview)
        prep(page, "https://plx.foundation/")
        page.evaluate("window.scrollTo(0, 380)")
        page.wait_for_timeout(1500)
        capture(page, "screenshot-03-deploy.png")

        # Extra frames for GIF / video (all real pages)
        extras = [
            ("https://app.plx.foundation/", "frame-app-home.png"),
            ("https://plx.foundation/plx-token", "frame-plx-token.png"),
            ("https://plx.foundation/pricing", "frame-pricing.png"),
        ]
        for url, fname in extras:
            prep(page, url)
            capture(page, fname)

        browser.close()
    print("done")


if __name__ == "__main__":
    main()
