#!/usr/bin/env python3
"""Frames App Store screenshots with a caption, the way most store listings do.

    store-frames.py [picks dir] [out dir]

Defaults: build/store-capture/picks -> build/store-capture/framed. Each shot in SHOTS gets a
world-color background, a caption in the game's font (Avenir Next Heavy), and the screenshot below
it with rounded corners and a soft shadow. Output matches the native capture dimensions,
with no alpha. All selected screenshots must have the same dimensions.
The captions sell the fun, not the mechanics.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 2868, 1320
UNIT = 1.0
FONT = ("/System/Library/Fonts/Avenir Next.ttc", 8)  # Avenir Next Heavy, as in the app

# ReefStyle.color(for:) in MathReef/ReefUI.swift.
CORAL = (250, 115, 107)
BLUE = (77, 148, 250)
PURPLE = (158, 115, 242)
GREEN = (41, 184, 148)
PINK = (242, 102, 179)

# (screenshot name in the picks folder, caption, background), in listing order.
SHOTS = [
    ("03-play-19", "Make learning fun", CORAL),
    ("05-wrong-44", "Every oops helps you learn", BLUE),
    ("01-home", "Dive into a reef of math", PURPLE),
    ("08-crown-40", "Earn stars and crowns", GREEN),
    ("07-exponents-16", "From first sums to exponents", PINK),
    ("04-addition-37", "Made for grades 1–5", CORAL),
    ("06-exponents-28", "Celebrate every win", BLUE),
    ("02-world", "Small steps, big progress", PURPLE),
]

SHOT_SCALE = 0.75
CORNER = 56
BORDER = 12


def shade(color, amount):
    """Lighter for amount > 0, darker for amount < 0."""
    if amount >= 0:
        return tuple(round(c + (255 - c) * amount) for c in color)
    return tuple(round(c * (1 + amount)) for c in color)


def background(color):
    top, bottom = shade(color, 0.18), shade(color, -0.22)
    column = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    image = column.resize((W, H))
    # A few soft bubbles, like the game's water.
    bubbles = Image.new("RGBA", (W, H))
    draw = ImageDraw.Draw(bubbles)
    for x, y, r in [(150, 220, 46), (260, 120, 22), (2700, 260, 38), (2600, 110, 18), (90, 1150, 30), (2780, 1180, 26)]:
        x, y, r = x * W / 2868, y * H / 1320, r * UNIT
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, 40), outline=(255, 255, 255, 110), width=max(1, round(5 * UNIT)))
    image.paste(bubbles, (0, 0), bubbles)
    return image


def rounded(image, radius):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=radius, fill=255)
    return mask


def frame(shot, caption, color):
    canvas = background(color)
    w, h = round(W * SHOT_SCALE), round(H * SHOT_SCALE)
    x, y = (W - w) // 2, H - h - round(64 * UNIT)

    # Soft shadow, then a white border, then the screenshot.
    shadow = Image.new("RGBA", (W, H))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x - BORDER, y - BORDER + round(24 * UNIT), x + w + BORDER, y + h + BORDER + round(24 * UNIT)), radius=CORNER + BORDER, fill=(0, 0, 40, 90)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28 * UNIT))
    canvas.paste(shadow, (0, 0), shadow)
    border = Image.new("RGB", (w + 2 * BORDER, h + 2 * BORDER), (255, 255, 255))
    canvas.paste(border, (x - BORDER, y - BORDER), rounded(border, CORNER + BORDER))
    screen = shot.resize((w, h), Image.LANCZOS)
    canvas.paste(screen, (x, y), rounded(screen, CORNER))

    # The caption, centered in the band above, with a soft shadow.
    size = round(132 * UNIT)
    font = ImageFont.truetype(FONT[0], size, index=FONT[1])
    while font.getlength(caption) > W * 0.9:
        size -= max(1, round(4 * UNIT))
        font = ImageFont.truetype(FONT[0], size, index=FONT[1])
    band = y - BORDER
    cx, cy = W // 2, band // 2 + round(4 * UNIT)
    glow = Image.new("RGBA", (W, H))
    ImageDraw.Draw(glow).text((cx, cy + round(6 * UNIT)), caption, font=font, fill=(0, 0, 40, 110), anchor="mm")
    glow = glow.filter(ImageFilter.GaussianBlur(8 * UNIT))
    canvas.paste(glow, (0, 0), glow)
    ImageDraw.Draw(canvas).text((cx, cy), caption, font=font, fill=(255, 255, 255), anchor="mm")
    return canvas


def main():
    global W, H, UNIT, CORNER, BORDER
    picks = Path(sys.argv[1] if len(sys.argv) > 1 else "build/store-capture/picks")
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "build/store-capture/framed")
    with Image.open(picks / f"{SHOTS[0][0]}.png") as first:
        W, H = first.size
    UNIT = min(W / 2868, H / 1320)
    CORNER, BORDER = round(56 * UNIT), round(12 * UNIT)
    # Validate every input before producing any output.
    for name, _, _ in SHOTS:
        with Image.open(picks / f"{name}.png") as shot:
            if shot.size != (W, H):
                sys.exit(f"{name}: expected {(W, H)}, got {shot.size}; recapture at the same device size")
    out.mkdir(parents=True, exist_ok=True)
    for index, (name, caption, color) in enumerate(SHOTS, 1):
        shot = Image.open(picks / f"{name}.png").convert("RGB")
        path = out / f"{index:02d}-{name.split('-', 1)[1]}.png"
        frame(shot, caption, color).save(path)
        print(f"{path}: {caption}")


if __name__ == "__main__":
    main()
