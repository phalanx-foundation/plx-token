"""Capture homepage build hero as screenshot-03."""

from __future__ import annotations

from pathlib import Path

from playwright.sync_api import sync_playwright

OUT = Path(r"D:\DATA TOOLS\PLX-ACTON\metadata\app-submission")
TG_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 "
    "Telegram-iOS/10.0"
)


def main() -> None:
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
        page.add_init_script(
            "sessionStorage.setItem('plx_event_popup_dismissed','1');"
            "localStorage.setItem('plx_event_popup_dismissed_at', String(Date.now()));"
        )
        page.goto(
            "https://plx.foundation/", wait_until="domcontentloaded", timeout=60000
        )
        page.wait_for_timeout(3500)
        path = OUT / "screenshot-03-deploy.png"
        page.screenshot(path=str(path), full_page=False)
        print("SAVED", path, path.stat().st_size)
        browser.close()


if __name__ == "__main__":
    main()
