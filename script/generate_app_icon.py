#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets"
ICONSET = ASSETS / "AppIcon.iconset"
ICNS = ASSETS / "AppIcon.icns"


def rounded_rectangle(draw: ImageDraw.ImageDraw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def render_icon(size: int) -> Image.Image:
    scale = 4
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    s = size * scale

    rounded_rectangle(
        draw,
        (0.07 * s, 0.07 * s, 0.93 * s, 0.93 * s),
        int(0.22 * s),
        fill=(31, 32, 35, 255),
        outline=(74, 76, 82, 255),
        width=max(1, int(0.012 * s)),
    )
    rounded_rectangle(
        draw,
        (0.20 * s, 0.22 * s, 0.80 * s, 0.73 * s),
        int(0.11 * s),
        fill=(242, 239, 232, 255),
        outline=(202, 198, 188, 255),
        width=max(1, int(0.014 * s)),
    )

    tail = [
        (0.34 * s, 0.72 * s),
        (0.30 * s, 0.84 * s),
        (0.45 * s, 0.72 * s),
    ]
    draw.polygon(tail, fill=(242, 239, 232, 255), outline=(202, 198, 188, 255))

    line_color = (82, 86, 93, 255)
    for y, width_factor in ((0.36, 0.42), (0.47, 0.35), (0.58, 0.26)):
        draw.rounded_rectangle(
            (0.32 * s, y * s, (0.32 + width_factor) * s, (y + 0.028) * s),
            radius=int(0.014 * s),
            fill=line_color,
        )

    trash_box = (0.58 * s, 0.58 * s, 0.78 * s, 0.80 * s)
    rounded_rectangle(
        draw,
        trash_box,
        int(0.025 * s),
        fill=(31, 32, 35, 255),
        outline=(244, 96, 96, 255),
        width=max(1, int(0.018 * s)),
    )
    draw.rounded_rectangle(
        (0.56 * s, 0.54 * s, 0.80 * s, 0.58 * s),
        radius=int(0.014 * s),
        fill=(244, 96, 96, 255),
    )
    for x in (0.64, 0.70):
        draw.line(
            (x * s, 0.62 * s, x * s, 0.76 * s),
            fill=(244, 96, 96, 255),
            width=max(1, int(0.012 * s)),
        )

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    ASSETS.mkdir(exist_ok=True)
    ICONSET.mkdir(exist_ok=True)

    specs = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    for name, size in specs.items():
        render_icon(size).save(ICONSET / name)

    subprocess.run(["/usr/bin/iconutil", "-c", "icns", "-o", str(ICNS), str(ICONSET)], check=True)
    print(ICNS)


if __name__ == "__main__":
    main()
