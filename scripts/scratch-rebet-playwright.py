#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Scratch Seeker → Saudaratoto re-bet via Playwright (stdout JSON only).

Env (from acton-worker):
  SITE_THIRD_BASE_URL, SITE_THIRD_USERNAME, SITE_THIRD_PASSWORD
  REBET_DIGITS, REBET_MODE (single|bulk), REBET_GUESS, REBET_STAKE_IDR
  REBET_DRY_RUN=1  → fill + Kirim #1 + stop before Kirim #2 (optional)

Submit flow: isi form → klik #kirimkan → rekap + native confirm('proses.???') → OK.
(Playwright must accept the dialog; dismissing = bet never posts.)
"""
from __future__ import annotations

import json
import os
import sys
import time
from typing import Any


def _env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


def _site_unit(stake_idr: int) -> str:
    # Rp1000 → 1.0 ; Rp100 → 0.1
    val = float(stake_idr) / 1000.0
    s = f"{val:.4f}".rstrip("0").rstrip(".")
    return s or "0"


def _game_path(digits: int) -> str:
    if digits == 5:
        return "/games/minigame/TM5DMobile"
    return "/games/tm/m17"


def _close_promos(page) -> list[str]:
    acts: list[str] = []
    selectors = [
        ".layui-layer-close",
        ".layui-layer-setwin .layui-layer-close1",
        ".swal2-close",
        ".modal.show .btn-close",
        "button:has-text('Tutup')",
        "button:has-text('Close')",
        ".close",
        "text=×",
        "#close",
    ]
    for _ in range(4):
        clicked = False
        for sel in selectors:
            try:
                locs = page.locator(sel)
                n = min(locs.count(), 6)
                for i in range(n):
                    el = locs.nth(i)
                    if el.is_visible(timeout=250):
                        el.click(timeout=1200)
                        acts.append(sel)
                        page.wait_for_timeout(350)
                        clicked = True
            except Exception:
                continue
        if not clicked:
            break
    return acts


def _login(page, base: str, user: str, password: str) -> None:
    page.goto(base.rstrip("/") + "/", wait_until="domcontentloaded", timeout=90000)
    page.wait_for_timeout(800)
    _close_promos(page)
    page.fill("#navbar_username", user)
    page.fill("#navbar_password", password)
    page.click("#submitlogin")
    page.wait_for_timeout(1500)
    _close_promos(page)
    if page.locator("#setuju").count() and page.locator("#setuju").first.is_visible(timeout=2000):
        page.click("#setuju")
        page.wait_for_timeout(1200)
        _close_promos(page)


def _open_game(page, base: str, digits: int) -> str:
    # Lobby first — direct deep-link can bounce depending on session.
    try:
        page.goto(base.rstrip("/") + "/lobby", wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(700)
        _close_promos(page)
    except Exception:
        pass

    path = _game_path(digits)
    page.goto(base.rstrip("/") + path, wait_until="domcontentloaded", timeout=90000)
    page.wait_for_timeout(2000)
    _close_promos(page)
    # Ensure 4D/3D/2D form tab first, THEN BET FULL (load resets type otherwise).
    if digits != 5:
        try:
            loc = page.locator("a[href*='/games/tm/load/4d/m17']").first
            if loc.count() and loc.is_visible(timeout=800):
                loc.click(timeout=2000)
                page.wait_for_timeout(900)
                _close_promos(page)
        except Exception:
            pass
        # BET FULL = changetype('B') via div.mntypel (user-canonical).
        try:
            if page.locator("div.mntypel").count():
                page.locator("div.mntypel").first.click(timeout=2000)
                page.wait_for_timeout(400)
            page.evaluate("() => { try { changetype('B'); } catch (e) {} }")
            page.wait_for_timeout(300)
        except Exception:
            try:
                page.evaluate("() => { try { changetype('B'); } catch (e) {} }")
            except Exception:
                pass
    else:
        for label in ("5D", "BET FULL", "Bet Full"):
            try:
                loc = page.get_by_text(label, exact=False).first
                if loc.is_visible(timeout=1000):
                    loc.click(timeout=2000)
                    page.wait_for_timeout(900)
                    break
            except Exception:
                continue
    _close_promos(page)

    # 5D often redirects / opens alwaysplaygames host — wait for row inputs
    if digits == 5:
        try:
            page.wait_for_url("**/*game5d*", timeout=20000)
        except Exception:
            pass
        page.wait_for_timeout(1500)
        _close_promos(page)
        # If still on portal, follow obvious game frame/link
        if page.locator("#r11n").count() == 0:
            for sel in [
                "iframe",
                "a[href*='game5d']",
                "a[href*='alwaysplaygames']",
                "a[href*='TM5D']",
            ]:
                try:
                    if sel == "iframe" and page.locator("iframe").count():
                        frame = page.frame_locator("iframe").first
                        if frame.locator("#r11n").count():
                            # switch context via content frame later — store URL
                            src = page.locator("iframe").first.get_attribute("src") or ""
                            if src:
                                page.goto(src, wait_until="domcontentloaded", timeout=90000)
                                page.wait_for_timeout(1500)
                            break
                    loc = page.locator(sel).first
                    if loc.count() and loc.is_visible(timeout=800):
                        with page.expect_navigation(timeout=20000):
                            loc.click(timeout=2000)
                        page.wait_for_timeout(1500)
                        break
                except Exception:
                    continue

    try:
        page.wait_for_selector("#r11n", timeout=20000)
    except Exception as exc:
        raise RuntimeError(f"game form #r11n not found at {page.url}: {exc}") from exc
    return page.url


def _set_input_value(page, selector: str, value: str, *, allow_force: bool = False) -> None:
    """Fill input. Prefer native enabled fill; force-JS only as last resort."""
    loc = page.locator(selector)
    if not loc.count():
        raise RuntimeError(f"missing input {selector}")
    try:
        if loc.is_enabled(timeout=2000):
            loc.fill(value, timeout=5000)
            return
    except Exception:
        pass
    if not allow_force:
        raise RuntimeError(f"input {selector} still disabled (site JS not ready)")
    page.evaluate(
        """([sel, val]) => {
          const el = document.querySelector(sel);
          if (!el) throw new Error('missing ' + sel);
          el.removeAttribute('disabled');
          el.disabled = false;
          el.value = val;
          for (const ev of ['input', 'change', 'keyup', 'blur']) {
            el.dispatchEvent(new Event(ev, { bubbles: true }));
          }
        }""",
        [selector, value],
    )


def _fill_row(page, row: int, *, digits: int, nomor: str, site_stake: str, bulk: bool) -> None:
    # Rows on site are indexed 11..20
    # Nomor MUST be typed so site keyup protect(event,row) enables stake cols.
    nomor_sel = f"#r{row}n"
    loc = page.locator(nomor_sel)
    if not loc.count():
        raise RuntimeError(f"missing input {nomor_sel}")
    loc.click(timeout=3000)
    try:
        loc.fill("")
    except Exception:
        pass
    page.type(nomor_sel, str(nomor), delay=80)
    try:
        loc.press("Tab")
    except Exception:
        pass
    page.wait_for_timeout(500)

    stake_suffix = {5: "5d", 4: "4d", 3: "3d", 2: "2d"}[digits]
    stake_sel = f"#r{row}{stake_suffix}"
    try:
        page.wait_for_function(
            """(sel) => {
              const el = document.querySelector(sel);
              return !!el && !el.disabled;
            }""",
            arg=stake_sel,
            timeout=6000,
        )
    except Exception as exc:
        raise RuntimeError(
            f"stake {stake_sel} not enabled after typing nomor={nomor}"
        ) from exc

    # Clear other stake columns only when enabled
    for suffix in ("5d", "4d", "3d", "2d"):
        if suffix == stake_suffix:
            continue
        sel = f"#r{row}{suffix}"
        if page.locator(sel).count():
            try:
                if page.locator(sel).is_enabled(timeout=300):
                    page.locator(sel).fill("")
            except Exception:
                pass

    _set_input_value(page, stake_sel, site_stake, allow_force=False)

    cb = page.locator(f"#check{row}")
    if cb.count():
        try:
            checked = cb.is_checked()
            if bulk and not checked:
                cb.check(force=True)
            elif (not bulk) and checked:
                cb.uncheck(force=True)
        except Exception:
            page.evaluate(
                """([sel, bulk]) => {
                  const el = document.querySelector(sel);
                  if (!el) return;
                  el.checked = !!bulk;
                  el.dispatchEvent(new Event('change', { bubbles: true }));
                }""",
                [f"#check{row}", bulk],
            )


def _click_visible(page, selectors: list[str], *, timeout_each: int = 2500) -> str | None:
    for sel in selectors:
        try:
            locs = page.locator(sel)
            n = min(locs.count(), 8)
            for i in range(n):
                loc = locs.nth(i)
                try:
                    loc.scroll_into_view_if_needed(timeout=1500)
                except Exception:
                    pass
                if loc.is_visible(timeout=timeout_each):
                    loc.click(timeout=4000)
                    return sel
        except Exception:
            continue
    # JS fallback for stubborn/offscreen controls
    for sel in selectors:
        try:
            ok = page.evaluate(
                """(sel) => {
                  const nodes = Array.from(document.querySelectorAll(sel));
                  const el = nodes.find((n) => {
                    const t = (n.innerText || n.textContent || n.value || '').trim().toLowerCase();
                    // skip hidden modal 'ya' when selecting #kirimkan for submit #1
                    return n.offsetParent !== null || t === 'kirim';
                  }) || nodes[0];
                  if (!el) return false;
                  el.scrollIntoView({block:'center'});
                  el.click();
                  return true;
                }""",
                sel,
            )
            if ok:
                return f"js:{sel}"
        except Exception:
            continue
    return None


def _kirim_selectors() -> list[str]:
    # User flow: dua kali "Kirim/submit" — bukan tombol "Ya".
    return [
        "button.btn-kirim",
        "button[name='cmdkirim']",
        "input[name='cmdkirim']",
        "[name='cmdkirim']",
        "button:has-text('Kirim')",
        "input[type='submit'][value='Kirim']",
        "input[type='button'][value='Kirim']",
    ]


def _click_last_visible_kirim(page) -> str | None:
    """Click the bottom-most visible Kirim (confirm-table submit #2)."""
    try:
        handle = page.evaluate(
            """() => {
              const sels = [
                "button.btn-kirim",
                "button[name='cmdkirim']",
                "input[name='cmdkirim']",
                "button",
                "input[type='submit']",
                "input[type='button']",
                "a",
              ];
              const seen = new Set();
              const nodes = [];
              for (const sel of sels) {
                for (const el of document.querySelectorAll(sel)) {
                  if (seen.has(el)) continue;
                  seen.add(el);
                  const t = ((el.innerText || el.textContent || el.value || '') + '').trim().toLowerCase();
                  if (t !== 'kirim' && !/\\bkirim\\b/.test(t)) continue;
                  const r = el.getBoundingClientRect();
                  const style = window.getComputedStyle(el);
                  if (r.width < 2 || r.height < 2) continue;
                  if (style.visibility === 'hidden' || style.display === 'none') continue;
                  if (style.opacity === '0') continue;
                  nodes.push({ el, top: r.top + window.scrollY, bottom: r.bottom + window.scrollY });
                }
              }
              if (!nodes.length) return null;
              nodes.sort((a, b) => a.bottom - b.bottom);
              const pick = nodes[nodes.length - 1].el;
              pick.scrollIntoView({ block: 'center' });
              pick.click();
              return {
                tag: pick.tagName,
                id: pick.id || '',
                name: pick.getAttribute('name') || '',
                class: (pick.className || '').toString().slice(0, 80),
                text: ((pick.innerText || pick.value || '') + '').trim().slice(0, 40),
              };
            }"""
        )
        if handle:
            return f"last-kirim:{handle.get('tag')}#{handle.get('id')}.{handle.get('class')}[{handle.get('text')}]"
    except Exception:
        pass
    # Fallback: last matching locator in DOM order
    for sel in _kirim_selectors():
        try:
            locs = page.locator(sel)
            n = locs.count()
            for i in range(n - 1, -1, -1):
                loc = locs.nth(i)
                if loc.is_visible(timeout=800):
                    loc.scroll_into_view_if_needed(timeout=1500)
                    loc.click(timeout=4000)
                    return f"locator-last:{sel}[{i}]"
        except Exception:
            continue
    return None


def _wait_confirm_table(page, timeout_ms: int = 8000) -> bool:
    """After Kirim #1, confirmation/rekap table should appear before Kirim #2."""
    deadline = time.time() + (timeout_ms / 1000.0)
    while time.time() < deadline:
        try:
            # Heuristic: extra table / ringkasan / total appears
            ok = page.evaluate(
                """() => {
                  const body = (document.body && document.body.innerText || '').toLowerCase();
                  if (body.includes('konfirm') || body.includes('ringkasan') || body.includes('total bayar') || body.includes('total bet')) {
                    return true;
                  }
                  const tables = document.querySelectorAll('table');
                  return tables.length >= 2;
                }"""
            )
            if ok:
                return True
        except Exception:
            pass
        page.wait_for_timeout(250)
    return False


def _submit_dual(page, dry_run: bool) -> dict[str, Any]:
    """Submit bet on Saudaratoto m17/5D.

    Real site handler (#kirimkan in game_4d.min.js):
      balanceProtect → build payload → window.confirm('proses.???') → POST /games/tm/send

    The on-page summary table is the rekap; the *final* gate is the native
    confirm dialog (OK/Cancel), not a second "Ya" button and not a second
    Kirim click. Playwright must accept that dialog or the bet never posts.
    """
    dialog_meta: dict[str, Any] = {"seen": False, "accepted": False, "message": None}

    def _on_dialog(dialog) -> None:
        dialog_meta["seen"] = True
        try:
            dialog_meta["message"] = (dialog.message or "")[:120]
        except Exception:
            dialog_meta["message"] = None
        try:
            if dry_run:
                dialog.dismiss()
                dialog_meta["accepted"] = False
            else:
                dialog.accept()
                dialog_meta["accepted"] = True
        except Exception:
            pass

    page.on("dialog", _on_dialog)

    # Prefer the real wired button from game_4d.min.js
    clicked = _click_visible(
        page,
        ["#kirimkan", "button#kirimkan", "button.btn-kirim[name='cmdkirim']", *_kirim_selectors()],
        timeout_each=2000,
    )
    if not clicked:
        raise RuntimeError("Kirim (#kirimkan) not found/visible")

    # Native confirm is sync inside the click handler; give ajax a moment after accept.
    page.wait_for_timeout(2500 if not dry_run else 1200)
    _close_promos(page)
    confirm_visible = _wait_confirm_table(page, timeout_ms=3000)

    if dry_run:
        return {
            "dry_run": True,
            "stopped_before_confirm": True,
            "submit1": clicked,
            "confirm_table_visible": confirm_visible,
            "native_confirm": dialog_meta,
        }

    if not dialog_meta.get("seen"):
        # Fallback: some skins may use a second on-page Kirim after rekap.
        confirmed = _click_last_visible_kirim(page)
        page.wait_for_timeout(2000)
        if not confirmed and not dialog_meta.get("accepted"):
            raise RuntimeError(
                "native confirm('proses.???') not shown and no second Kirim found"
            )
        return {
            "dry_run": False,
            "confirmed": True,
            "submit1": clicked,
            "submit2": confirmed,
            "confirm_table_visible": confirm_visible,
            "native_confirm": dialog_meta,
        }

    if not dialog_meta.get("accepted"):
        raise RuntimeError("native confirm was not accepted")

    # Wait for success / error marker from ajax handler
    try:
        page.wait_for_function(
            """() => {
              const el = document.getElementById('returninfo');
              if (!el) return false;
              const t = (el.innerText || el.textContent || '').toLowerCase();
              return t.includes('success') || t.includes('error') || t.includes('proses');
            }""",
            timeout=8000,
        )
    except Exception:
        pass
    page.wait_for_timeout(800)

    return_info = None
    try:
        return_info = page.evaluate(
            "() => (document.getElementById('returninfo')||{}).innerText || null"
        )
    except Exception:
        pass

    return {
        "dry_run": False,
        "confirmed": True,
        "submit1": clicked,
        "submit2": "native_confirm:proses",
        "confirm_table_visible": confirm_visible,
        "native_confirm": dialog_meta,
        "returninfo": return_info,
    }


def _read_balance_idr(page) -> float | None:
    import re

    try:
        body = page.locator("body").inner_text(timeout=4000)
    except Exception:
        body = ""
    m = re.search(r"IDR\s*([0-9][0-9.,]*)", body, re.I)
    if m:
        raw = m.group(1).replace(",", "")
        try:
            return float(raw)
        except ValueError:
            return None
    try:
        el = page.locator("[id*='balance' i]").first
        if el.count():
            txt = (el.inner_text(timeout=1000) or "").strip().replace(",", "")
            return float(txt) if txt else None
    except Exception:
        return None
    return None


def _transaction_row_count(page, base: str) -> int:
    try:
        page.goto(base.rstrip("/") + "/transaction", wait_until="domcontentloaded", timeout=45000)
        page.wait_for_timeout(1200)
        _close_promos(page)
        tables = page.locator("table")
        if tables.count() == 0:
            return 0
        # data rows = tr with td (skip header-only)
        rows = tables.first.locator("tr").filter(has=page.locator("td"))
        return int(rows.count())
    except Exception:
        return -1


def _detect_place_failure(page) -> str | None:
    # NOTE: m17 HTML often contains sticky text "Bettingan Gagal!" even when idle.
    # Only treat freshly visible toast/modal/alert as failure — not raw page source.
    try:
        visible = page.evaluate(
            """() => {
              const needles = [
                'bettingan gagal',
                'bet gagal',
                'gagal dikirim',
                'transaksi gagal',
                'saldo tidak cukup',
                'saldo kurang',
                'periode sudah tutup',
              ];
              const nodes = Array.from(document.querySelectorAll(
                '.swal2-container, .layui-layer, .modal.show, .alert, .toast, #errmsg, .error, .swal2-html-container, .layui-layer-content'
              ));
              for (const el of nodes) {
                const t = ((el.innerText || el.textContent || '') + '').trim().toLowerCase();
                if (!t) continue;
                const r = el.getBoundingClientRect();
                const s = getComputedStyle(el);
                if (r.width < 2 || r.height < 2) continue;
                if (s.visibility === 'hidden' || s.display === 'none' || s.opacity === '0') continue;
                for (const n of needles) {
                  if (t.includes(n)) return n;
                }
              }
              return null;
            }"""
        )
        if visible:
            return str(visible)
    except Exception:
        pass
    return None


def _parse_rows(digits: int, mode: str, guess: str, stake_idr: int) -> list[dict[str, Any]]:
    """Build site rows. Optional REBET_ROWS_JSON overrides; max 10 per submit batch."""
    raw = _env("REBET_ROWS_JSON")
    if raw:
        rows = json.loads(raw)
        if not isinstance(rows, list) or not rows:
            raise RuntimeError("REBET_ROWS_JSON must be non-empty list")
        out: list[dict[str, Any]] = []
        for item in rows:
            d = int(item.get("digits") or digits)
            nomor = str(item.get("nomor") or item.get("guess") or "").strip().zfill(d)[-d:]
            sidr = int(item.get("stake_idr") or stake_idr)
            out.append(
                {
                    "nomor": nomor,
                    "digits": d,
                    "site_stake": str(item.get("site_stake") or _site_unit(sidr)),
                    "bulk": bool(item.get("bulk", mode == "bulk")),
                }
            )
        return out
    if not guess or stake_idr <= 0:
        raise RuntimeError("REBET_GUESS and REBET_STAKE_IDR required")
    return [
        {
            "nomor": guess.strip().zfill(digits)[-digits:],
            "digits": digits,
            "site_stake": _site_unit(stake_idr),
            "bulk": mode == "bulk",
        }
    ]


def run() -> dict[str, Any]:
    base = _env("SITE_THIRD_BASE_URL")
    user = _env("SITE_THIRD_USERNAME")
    password = _env("SITE_THIRD_PASSWORD")
    digits = int(_env("REBET_DIGITS", "0") or "0")
    mode = (_env("REBET_MODE", "single") or "single").lower()
    guess = _env("REBET_GUESS")
    stake_idr = int(float(_env("REBET_STAKE_IDR", "0") or "0"))
    dry_run = _env("REBET_DRY_RUN", "").lower() in {"1", "true", "yes", "on"}
    bet_id = _env("REBET_BET_ID")

    if not base or not user or not password:
        raise RuntimeError("SITE_THIRD_BASE_URL/USERNAME/PASSWORD required")
    if digits not in (2, 3, 4, 5):
        raise RuntimeError(f"invalid REBET_DIGITS={digits}")

    rows = _parse_rows(digits, mode, guess, stake_idr)
    if len(rows) > 10:
        # Caller should chunk; still enforce hard cap here.
        raise RuntimeError(f"max 10 rows per submit, got {len(rows)}")

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1400, "height": 1000})
        page = context.new_page()
        try:
            _login(page, base, user, password)
            # Baseline site proof (lobby balance + open tx count)
            page.goto(base.rstrip("/") + "/lobby", wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(800)
            _close_promos(page)
            bal_before = _read_balance_idr(page)
            tx_before = _transaction_row_count(page, base)

            final_url = _open_game(page, base, digits)
            for i, row in enumerate(rows):
                _fill_row(
                    page,
                    11 + i,
                    digits=int(row["digits"]),
                    nomor=str(row["nomor"]),
                    site_stake=str(row["site_stake"]),
                    bulk=bool(row["bulk"]),
                )
            submit_meta = _submit_dual(page, dry_run=dry_run)
            fail = _detect_place_failure(page)
            if fail and not dry_run:
                raise RuntimeError(f"site place failure: {fail}")

            site_proof: dict[str, Any] = {
                "balance_before": bal_before,
                "tx_rows_before": tx_before,
            }
            executed = False
            status = "dry_run" if dry_run else "unverified"

            if dry_run:
                return {
                    "ok": True,
                    "status": status,
                    "executed": False,
                    "bet_id": bet_id or None,
                    "digits": digits,
                    "mode": mode,
                    "nomor": rows[0]["nomor"] if rows else None,
                    "site_stake": rows[0]["site_stake"] if rows else None,
                    "stake_idr": stake_idr,
                    "rows": rows,
                    "game_url": final_url,
                    "bulk": mode == "bulk",
                    "site_proof": site_proof,
                    **submit_meta,
                    "ts": int(time.time()),
                }

            # Post-confirm proof: balance drop and/or new transaction row.
            page.goto(base.rstrip("/") + "/lobby", wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(900)
            _close_promos(page)
            bal_after = _read_balance_idr(page)
            tx_after = _transaction_row_count(page, base)
            site_proof.update(
                {
                    "balance_after": bal_after,
                    "tx_rows_after": tx_after,
                }
            )
            expected_debit = 0.0
            for row in rows:
                try:
                    expected_debit += float(row["site_stake"])
                except Exception:
                    pass
            balance_ok = (
                bal_before is not None
                and bal_after is not None
                and (bal_before - bal_after) >= max(0.01, expected_debit * 0.5)
            )
            tx_ok = tx_before >= 0 and tx_after > tx_before
            site_proof["balance_ok"] = bool(balance_ok)
            site_proof["tx_ok"] = bool(tx_ok)
            site_proof["expected_debit"] = expected_debit

            if not (balance_ok or tx_ok):
                raise RuntimeError(
                    "site proof missing after confirm "
                    f"(bal {bal_before}->{bal_after}, tx {tx_before}->{tx_after}, "
                    f"expected_debit={expected_debit})"
                )

            executed = True
            status = "placed"
            return {
                "ok": True,
                "status": status,
                "executed": executed,
                "bet_id": bet_id or None,
                "digits": digits,
                "mode": mode,
                "nomor": rows[0]["nomor"] if rows else None,
                "site_stake": rows[0]["site_stake"] if rows else None,
                "stake_idr": stake_idr,
                "rows": rows,
                "game_url": final_url,
                "bulk": mode == "bulk",
                "site_proof": site_proof,
                **submit_meta,
                "ts": int(time.time()),
            }
        finally:
            browser.close()


def main() -> int:
    try:
        result = run()
        print(json.dumps(result))
        return 0
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"ok": False, "error": str(exc)[:500]}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
