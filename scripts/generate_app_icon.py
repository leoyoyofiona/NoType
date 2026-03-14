#!/usr/bin/env python3

from pathlib import Path
import math
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources" / "notype" / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
ICNS = RESOURCES / "AppIcon.icns"


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def gradient_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    top = (20, 82, 255)
    bottom = (7, 24, 62)
    glow = (82, 201, 255)

    for y in range(size):
        for x in range(size):
            tx = x / max(size - 1, 1)
            ty = y / max(size - 1, 1)
            base = tuple(lerp(top[i], bottom[i], ty) for i in range(3))
            dx = tx - 0.72
            dy = ty - 0.25
            dist = math.sqrt(dx * dx + dy * dy)
            bloom = max(0.0, 1.0 - dist * 2.6)
            color = tuple(min(255, lerp(base[i], glow[i], bloom * 0.55)) for i in range(3))
            pixels[x, y] = (*color, 255)

    return image


def rounded_panel(size: int) -> Image.Image:
    image = gradient_background(size)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    margin = int(size * 0.06)
    radius = int(size * 0.24)
    shadow_draw.rounded_rectangle(
        [margin, margin + int(size * 0.03), size - margin, size - margin],
        radius=radius,
        fill=(0, 0, 0, 125),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=int(size * 0.04)))
    image.alpha_composite(shadow)

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=radius,
        fill=(255, 255, 255, 28),
        outline=(255, 255, 255, 72),
        width=max(2, size // 128),
    )
    return image


def paint_glyph(base: Image.Image) -> Image.Image:
    size = base.width
    image = base.copy()
    draw = ImageDraw.Draw(image)

    stroke = max(6, size // 24)
    mic_w = int(size * 0.18)
    mic_h = int(size * 0.28)
    mic_x = int(size * 0.29)
    mic_y = int(size * 0.24)
    stem_bottom = int(size * 0.69)
    color = (247, 252, 255, 255)
    accent = (117, 228, 255, 255)

    draw.rounded_rectangle(
        [mic_x, mic_y, mic_x + mic_w, mic_y + mic_h],
        radius=int(mic_w * 0.48),
        outline=color,
        width=stroke,
    )
    draw.line(
        [(mic_x + mic_w // 2, mic_y + mic_h), (mic_x + mic_w // 2, stem_bottom - int(size * 0.08))],
        fill=color,
        width=stroke,
    )
    draw.arc(
        [mic_x - int(size * 0.06), mic_y + int(size * 0.05), mic_x + mic_w + int(size * 0.06), stem_bottom - int(size * 0.08)],
        start=15,
        end=165,
        fill=color,
        width=stroke,
    )
    draw.line(
        [(mic_x + mic_w // 2 - int(size * 0.08), stem_bottom), (mic_x + mic_w // 2 + int(size * 0.08), stem_bottom)],
        fill=color,
        width=stroke,
    )

    arrow_width = max(6, size // 26)
    left = [
        (int(size * 0.57), int(size * 0.38)),
        (int(size * 0.78), int(size * 0.38)),
        (int(size * 0.70), int(size * 0.30)),
    ]
    right = [
        (int(size * 0.43), int(size * 0.63)),
        (int(size * 0.22), int(size * 0.63)),
        (int(size * 0.30), int(size * 0.71)),
    ]

    draw.line(left[:2], fill=accent, width=arrow_width)
    draw.line([left[1], left[2]], fill=accent, width=arrow_width)
    draw.line([left[1], (int(size * 0.70), int(size * 0.46))], fill=accent, width=arrow_width)

    draw.line(right[:2], fill=accent, width=arrow_width)
    draw.line([right[1], right[2]], fill=accent, width=arrow_width)
    draw.line([right[1], (int(size * 0.30), int(size * 0.55))], fill=accent, width=arrow_width)

    return image


def write_iconset() -> None:
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True, exist_ok=True)

    base = paint_glyph(rounded_panel(1024))
    for size in [16, 32, 64, 128, 256, 512]:
        for scale in [1, 2]:
            actual = size * scale
            output = base.resize((actual, actual), Image.Resampling.LANCZOS)
            suffix = f"{size}x{size}"
            name = f"icon_{suffix}{'@2x' if scale == 2 else ''}.png"
            output.save(ICONSET / name)


def build_icns() -> None:
    write_iconset()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)


if __name__ == "__main__":
    build_icns()
    print(ICNS)
