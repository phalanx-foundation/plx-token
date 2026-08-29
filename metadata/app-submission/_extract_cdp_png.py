"""Save Cursor browser CDP captureScreenshot JSON to PNG and optionally resize."""
from __future__ import annotations

import base64
import json
import re
import sys
from pathlib import Path

from PIL import Image


def extract_data(raw: str) -> bytes:
    try:
        obj = json.loads(raw)
        data = obj.get("result", {}).get("data") or obj.get("data")
    except json.JSONDecodeError:
        m = re.search(r'"data":"([^"]+)"', raw)
        data = m.group(1) if m else None
    if not data:
        raise SystemExit("no base64 data")
    return base64.b64decode(data)


def main() -> None:
    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    tw = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    th = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(extract_data(src.read_text(encoding="utf-8")))
    if tw and th:
        im = Image.open(out).convert("RGB")
        im = im.resize((tw, th), Image.Resampling.LANCZOS)
        im.save(out, optimize=True)
    print(out, out.stat().st_size)


if __name__ == "__main__":
    main()
