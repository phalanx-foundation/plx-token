"""Compose a premium 640x360 Telegram Mini App thumbnail from real PLX assets."""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DASH = ROOT / "metadata" / "dashboard.jpg"
LOGO = ROOT / "toolkit-staging" / "web" / "public" / "plx-logo.png"
OUT_HI = ROOT / "metadata" / "telegram-miniapp-1920x1080-premium.png"
OUT_TG = ROOT / "metadata" / "telegram-miniapp-640x360-premium.jpg"

W, H = 1920, 1080
FONT_B = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_SB = r"C:\Windows\Fonts\seguisb.ttf"
FONT_R = r"C:\Windows\Fonts\segoeui.ttf"


def np_to_img(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def gradient_bg(w: int, h: int) -> Image.Image:
    xs = np.linspace(0, 1, w, dtype=np.float32)
    ys = np.linspace(0, 1, h, dtype=np.float32)
    xx, yy = np.meshgrid(xs, ys)
    r = 4 + 6 * xx * 0.35 + 4 * yy * 0.15
    g = 8 + 12 * xx
    b = 14 + 22 * xx * 0.65 + 10 * (1 - yy)
    a = np.full((h, w), 255.0, dtype=np.float32)
    return np_to_img(np.dstack([r, g, b, a]))


def hex_grid(w: int, h: int, spacing: int = 64) -> Image.Image:
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    step_y = int(spacing * math.sqrt(3) / 2)
    for row, y in enumerate(range(-spacing, h + spacing, step_y)):
        ox = spacing / 2 if row % 2 else 0
        x = -spacing + ox
        while x < w + spacing:
            pts = [
                (
                    x + (spacing / 2) * math.cos(math.radians(60 * i - 30)),
                    y + (spacing / 2) * math.sin(math.radians(60 * i - 30)),
                )
                for i in range(6)
            ]
            draw.line(pts + [pts[0]], fill=(56, 189, 248, 22), width=1)
            x += spacing
    return layer.filter(ImageFilter.GaussianBlur(0.3))


def scale_cover(im: Image.Image, tw: int, th: int, bias_x: float = 0.62, bias_y: float = 0.38) -> Image.Image:
    iw, ih = im.size
    scale = max(tw / iw, th / ih)
    nw, nh = int(iw * scale), int(ih * scale)
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    left = int((nw - tw) * bias_x)
    top = int((nh - th) * bias_y)
    left = max(0, min(left, nw - tw))
    top = max(0, min(top, nh - th))
    return im.crop((left, top, left + tw, top + th))


def horizontal_fade(im: Image.Image, start: float, end: float, max_a: int) -> Image.Image:
    w, h = im.size
    im = im.convert("RGBA")
    arr = np.array(im, dtype=np.float32)
    t = np.linspace(0, 1, w, dtype=np.float32)
    u = np.clip((t - start) / max(end - start, 1e-6), 0, 1)
    u = u * u * (3 - 2 * u)
    fade = (u * max_a).astype(np.float32)
    arr[:, :, 3] *= fade[None, :] / 255.0
    return np_to_img(arr)


def left_veil(w: int, h: int, until: float = 0.58, peak: int = 188) -> Image.Image:
    t = np.linspace(0, 1, w, dtype=np.float32)
    alpha = np.where(t <= until, peak * np.power(1 - t / until, 1.25), 0)
    a = np.repeat(alpha[None, :], h, axis=0)
    r = np.full_like(a, 3)
    g = np.full_like(a, 8)
    b = np.full_like(a, 16)
    return np_to_img(np.dstack([r, g, b, a]))


def vignette(w: int, h: int) -> Image.Image:
    ys, xs = np.ogrid[:h, :w]
    cx, cy = w * 0.62, h * 0.46
    d = np.hypot(xs - cx, ys - cy)
    maxd = math.hypot(w, h) * 0.58
    n = d / maxd
    a = np.clip((n - 0.70) * 280, 0, 150)
    z = np.zeros_like(a)
    return np_to_img(np.dstack([z, z, z, a]))


def circular_logo(src: Image.Image, size: int) -> Image.Image:
    im = src.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((2, 2, size - 3, size - 3), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0))
    out.putalpha(mask)
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.ellipse((3, 3, size - 4, size - 4), outline=(56, 189, 248, 170), width=3)
    rd.ellipse((8, 8, size - 9, size - 9), outline=(212, 175, 90, 70), width=1)
    return Image.alpha_composite(out, ring)


def glow_layer(sprite: Image.Image, radius: int, color: tuple[int, int, int], strength: float) -> Image.Image:
    alpha = sprite.split()[-1].filter(ImageFilter.GaussianBlur(radius))
    glow = Image.new("RGBA", sprite.size, color + (0,))
    glow.putalpha(ImageEnhance.Brightness(alpha).enhance(strength))
    return glow


def text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def compose() -> None:
    canvas = gradient_bg(W, H)
    canvas = Image.alpha_composite(canvas, hex_grid(W, H))

    dash = Image.open(DASH).convert("RGBA")
    dash = ImageEnhance.Contrast(dash).enhance(1.10)
    dash = ImageEnhance.Color(dash).enhance(1.06)
    dash = scale_cover(dash, W, H, bias_x=0.78, bias_y=0.28)
    grade = Image.new("RGBA", (W, H), (6, 28, 56, 36))
    dash = Image.alpha_composite(dash, grade)
    dash = horizontal_fade(dash, start=0.40, end=0.70, max_a=230)
    canvas = Image.alpha_composite(canvas, dash)
    canvas = Image.alpha_composite(canvas, left_veil(W, H))

    logo = circular_logo(Image.open(LOGO), 288)
    glow = glow_layer(logo, 28, (14, 165, 233), 0.9)
    gold = glow_layer(logo, 12, (212, 175, 90), 0.35)
    lx, ly = 88, 396
    canvas.alpha_composite(glow, (lx - 8, ly - 8))
    canvas.alpha_composite(gold, (lx, ly))
    canvas.alpha_composite(logo, (lx, ly))

    draw = ImageDraw.Draw(canvas)
    font_eye = ImageFont.truetype(FONT_SB, 26)
    font_title = ImageFont.truetype(FONT_B, 78)
    font_hook = ImageFont.truetype(FONT_SB, 36)
    font_sub = ImageFont.truetype(FONT_R, 26)
    font_cta = ImageFont.truetype(FONT_SB, 24)
    font_micro = ImageFont.truetype(FONT_R, 20)

    tx, ty = 420, 268
    draw.text((tx, ty), "TON MINI APP   ·   AUDITED JETTON", font=font_eye, fill=(125, 211, 252, 230))

    title = "Phalanx Toolkit"
    ty2 = ty + 48
    draw.text((tx + 1, ty2 + 2), title, font=font_title, fill=(8, 40, 80, 90))
    draw.text((tx, ty2), title, font=font_title, fill=(248, 250, 252, 255))

    ty3 = ty2 + 98
    draw.text((tx, ty3), "Deploy your token on TON.", font=font_hook, fill=(226, 232, 240, 250))
    draw.text((tx, ty3 + 50), "No code.  No CLI.  One tap in Telegram.", font=font_sub, fill=(147, 197, 253, 230))

    line_y = ty3 + 102
    draw.line((tx, line_y, tx + 240, line_y), fill=(56, 189, 248, 200), width=2)

    bw, bh = 248, 58
    bx, by = tx, line_y + 32
    glow_btn = Image.new("RGBA", (bw + 36, bh + 36), (0, 0, 0, 0))
    ImageDraw.Draw(glow_btn).rounded_rectangle((6, 6, bw + 30, bh + 30), 16, fill=(14, 165, 233, 80))
    canvas.alpha_composite(glow_btn.filter(ImageFilter.GaussianBlur(9)), (bx - 18, by - 18))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((bx, by, bx + bw, by + bh), 13, fill=(14, 165, 233, 240), outline=(186, 230, 253, 170), width=1)
    cta = "Deploy now   →"
    cw, ch = text_size(draw, cta, font_cta)
    draw.text((bx + (bw - cw) / 2, by + (bh - ch) / 2 - 2), cta, font=font_cta, fill=(4, 16, 32, 255))
    draw.text((tx, by + bh + 22), "app.plx.foundation", font=font_micro, fill=(148, 163, 184, 200))

    draw.rectangle((0, 0, W, 2), fill=(56, 189, 248, 80))
    draw.rectangle((0, H - 2, W, H), fill=(56, 189, 248, 60))
    canvas = Image.alpha_composite(canvas, vignette(W, H))

    canvas.convert("RGB").save(OUT_HI, "PNG", optimize=True)
    canvas.resize((640, 360), Image.Resampling.LANCZOS).convert("RGB").save(
        OUT_TG, "JPEG", quality=91, optimize=True, subsampling=1
    )
    print(f"saved {OUT_HI}")
    print(f"saved {OUT_TG} ({OUT_TG.stat().st_size} bytes)")


if __name__ == "__main__":
    compose()
