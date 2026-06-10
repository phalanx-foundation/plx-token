"""Load ROOT .env into os.environ (gitignored). Idempotent."""

from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
_ENV_LINE = re.compile(r"^\s*([^#=]+)=(.*)$")


def load_project_dotenv() -> bool:
    env_file = Path(os.environ.get("PLX_ENV_FILE", ROOT / ".env"))
    if not env_file.is_file():
        return False
    for line in env_file.read_text(encoding="utf-8", errors="replace").splitlines():
        m = _ENV_LINE.match(line)
        if not m:
            continue
        key = m.group(1).strip()
        val = m.group(2).strip().strip('"').strip("'")
        if key and val and os.environ.get(key, "").strip() == "":
            os.environ[key] = val
    if not os.environ.get("TONAPI_KEY") and os.environ.get("CONSOLE_TOKEN"):
        os.environ["TONAPI_KEY"] = os.environ["CONSOLE_TOKEN"]
    if not os.environ.get("TOKEN_TELEGRAM_BOT"):
        for alias in ("TELEGRAM_BOT_TOKEN", "TELEGRAM_TOKEN"):
            if os.environ.get(alias):
                os.environ["TOKEN_TELEGRAM_BOT"] = os.environ[alias]
                break
    return True
