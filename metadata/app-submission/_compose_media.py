"""Compose demo MP4 + preview GIF from REAL captured screenshots only."""
from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(r"D:\DATA TOOLS\PLX-ACTON\metadata\app-submission")
W, H = 900, 1600
GIF_W, GIF_H = 640, 360

REAL_FRAMES = [
    OUT / "screenshot-01-plx-app.png",
    OUT / "screenshot-02-dashboard.png",
    OUT / "screenshot-03-deploy.png",
    OUT / "frame-app-home.png",
    OUT / "frame-plx-token.png",
    OUT / "frame-pricing.png",
]


def contain(im: Image.Image, tw: int, th: int) -> Image.Image:
    canvas = Image.new("RGB", (tw, th), (6, 7, 10))
    im = im.convert("RGB")
    scale = min(tw / im.width, th / im.height)
    nw, nh = max(1, int(im.width * scale)), max(1, int(im.height * scale))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas.paste(im, ((tw - nw) // 2, (th - nh) // 2))
    return canvas


def title_card(title: str, sub: str) -> Image.Image:
    canvas = Image.new("RGB", (W, H), (6, 7, 10))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, W, 6), fill=(6, 182, 212))
    try:
        font_l = ImageFont.truetype("arial.ttf", 52)
        font_s = ImageFont.truetype("arial.ttf", 26)
    except OSError:
        font_l = font_s = ImageFont.load_default()
    logo = OUT / "icon-512.png"
    if logo.exists():
        mark = Image.open(logo).convert("RGBA").resize((140, 140), Image.Resampling.LANCZOS)
        canvas.paste(mark, ((W - 140) // 2, 460), mark)
    bbox = draw.textbbox((0, 0), title, font=font_l)
    draw.text(((W - (bbox[2] - bbox[0])) // 2, 640), title, fill=(248, 250, 252), font=font_l)
    if sub:
        bbox2 = draw.textbbox((0, 0), sub, font=font_s)
        draw.text(((W - (bbox2[2] - bbox2[0])) // 2, 720), sub, fill=(148, 163, 184), font=font_s)
    return canvas


def crop_gif_frame(im: Image.Image) -> Image.Image:
    """Center-crop portrait screenshot to 640x360 (real UI slice)."""
    im = im.convert("RGB")
    # take upper-middle band where hero/content lives
    target_ratio = GIF_W / GIF_H
    src_ratio = im.width / im.height
    if src_ratio > target_ratio:
        nh = im.height
        nw = int(nh * target_ratio)
        left = (im.width - nw) // 2
        top = int(im.height * 0.08)
        crop = im.crop((left, top, left + nw, min(top + int(nw / target_ratio), im.height)))
    else:
        nw = im.width
        nh = int(nw / target_ratio)
        top = int(im.height * 0.06)
        crop = im.crop((0, top, nw, min(top + nh, im.height)))
    return crop.resize((GIF_W, GIF_H), Image.Resampling.LANCZOS)


def main() -> None:
    frames = [p for p in REAL_FRAMES if p.exists()]
    if len(frames) < 3:
        raise SystemExit(f"Need real captures; found {len(frames)}")

    tmp = Path(tempfile.mkdtemp(prefix="plx-real-demo-"))
    try:
        seq: list[Image.Image] = [title_card("Phalanx Toolkit", "No-code audited Jettons on TON")]
        for p in frames:
            seq.append(contain(Image.open(p), W, H))
        seq.append(title_card("plx.foundation", "Open in Telegram · @phalanxfoundationbot"))

        idx = 0
        for im in seq:
            repeats = 3 if idx == 0 or idx == len(seq) - 1 else 4
            rgb = im.convert("RGB")
            for _ in range(repeats):
                rgb.save(tmp / f"f{idx:04d}.png")
                idx += 1

        mp4 = OUT / "demo-plx-app-900x1600.mp4"
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-framerate",
                "1",
                "-i",
                str(tmp / "f%04d.png"),
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-crf",
                "22",
                "-movflags",
                "+faststart",
                str(mp4),
            ],
            check=True,
        )
        print("MP4", mp4, mp4.stat().st_size)

        gif_frames = [crop_gif_frame(Image.open(p)) for p in frames[:6]]
        gif_path = OUT / "preview-640x360.gif"
        gif_frames[0].save(
            gif_path,
            save_all=True,
            append_images=gif_frames[1:],
            duration=1100,
            loop=0,
            optimize=True,
        )
        print("GIF", gif_path, gif_path.stat().st_size)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
