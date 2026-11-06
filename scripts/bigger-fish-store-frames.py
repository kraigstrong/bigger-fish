#!/usr/bin/env python3
"""Captions Bigger Fish's App Store screenshots, in the trailer's style.

    scripts/bigger-fish-store-frames.py [--only dodge,eat] <captures dir> <out dir>

The captures are scripts/bigger-fish-store-capture.sh's screenshots (NN-<moment>.png, at any one App Store size).
Each shot in SHOTS gets its caption in the game's typeface (Avenir Next Heavy), in listing order: the gameplay full
size, with no device frame, and the caption over a soft dark band across the top (Kraig: "I like A. No frame").
Output keeps the captures' size, with no alpha, as App Store Connect wants. Upload with appstore/push.py media.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = ("/System/Library/Fonts/Avenir Next.ttc", 8)  # Avenir Next Heavy, as in the game

# (capture, caption), in listing order: the strongest single image first and its pair, the two ways to play, each
# world's idea, the
# shop, and where it goes. The app's own screens (in INSET) have their titles at the top, where an overlaid caption
# would land, so they're shrunk a little over a blur of themselves instead.
SHOTS = [
    ("dodge", "DODGE BIGGER FISH"),
    ("eat", "EAT SMALLER ONES"),
    ("home", "TWO WAYS TO PLAY"),
    ("open-water", "GATHER PEARLS IN THE OPEN WATER"),
    ("jelly-tops", "BOUNCE OFF JELLYFISH"),
    ("kelp-shadows", "WHAT'S HIDING IN THE KELP?"),
    ("sunset-hooks", "LEAVE THE BAIT"),
    ("midnight-light", "LIGHT THE WAY"),
    ("shop", "CUSTOMIZE YOUR FISH"),
    ("deep-end", "CONQUER EACH WORLD"),
]
INSET = {"home", "shop", "deep-end"}


def font_for(caption, size, width):
    font = ImageFont.truetype(FONT[0], size, index=FONT[1])
    while font.getlength(caption) > width:
        size -= 4
        font = ImageFont.truetype(FONT[0], size, index=FONT[1])
    return font


def text(canvas, caption, font, center, shadow_color=(4, 12, 34, 150)):
    """The caption, centered, over a soft shadow of itself."""
    w, h = canvas.size
    unit = h / 1320
    glow = Image.new("RGBA", (w, h))
    ImageDraw.Draw(glow).text((center[0], center[1] + 6 * unit), caption, font=font, fill=shadow_color, anchor="mm")
    canvas.paste(glow.filter(ImageFilter.GaussianBlur(10 * unit)), (0, 0), glow.filter(ImageFilter.GaussianBlur(10 * unit)))
    ImageDraw.Draw(canvas).text(center, caption, font=font, fill=(255, 255, 255), anchor="mm")


def overlay(shot, caption):
    """The gameplay full size, the caption over a soft dark band across the top."""
    w, h = shot.size
    unit = min(w / 2868, h / 1320)
    canvas = shot.convert("RGB")
    band_height = round(h * 0.30)
    ramp = Image.linear_gradient("L").rotate(180).resize((w, band_height)).point(lambda v: round(v * 0.62))
    tint = Image.new("RGBA", (w, band_height), (4, 12, 34, 0))
    tint.putalpha(ramp)
    canvas.paste(tint, (0, 0), tint)
    font = font_for(caption, round(118 * unit), w * 0.86)
    text(canvas, caption, font, (w // 2, round(h * 0.095)))
    return canvas


def inset(shot, caption):
    """An app screen shrunk under a caption band, over a soft, darkened blur of itself: no border."""
    w, h = shot.size
    unit = min(w / 2868, h / 1320)
    top = round(h * 0.17)
    sw, sh = round(w * (h - top) / h), h - top
    x = (w - sw) // 2
    full = shot.convert("RGB")
    canvas = full.filter(ImageFilter.GaussianBlur(60 * unit))
    canvas = Image.blend(canvas, Image.new("RGB", (w, h), (4, 12, 34)), 0.35)
    canvas.paste(full.resize((sw, sh), Image.LANCZOS), (x, top))
    font = font_for(caption, round(118 * unit), w * 0.86)
    text(canvas, caption, font, (w // 2, top // 2 + round(6 * unit)))
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", help="comma-separated captures to frame (dodge,sunset-hooks,...)")
    parser.add_argument("captures", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    found = {p.stem.split("-", 1)[1]: p for p in args.captures.glob("[0-9][0-9]-*.png")}
    missing = [name for name, _ in SHOTS if name not in found]
    if missing:
        sys.exit(f"missing captures: {', '.join(missing)}")
    only = set(args.only.split(",")) if args.only else None
    args.out.mkdir(parents=True, exist_ok=True)
    if not only:
        # A folder framed for an older listing keeps its shots under their old numbers; push.py media uploads every PNG
        # in it, so whatever isn't in this listing goes.
        current = {f"{index:02d}-{name}.png" for index, (name, _) in enumerate(SHOTS, 1)}
        for stale in args.out.glob("[0-9][0-9]-*.png"):
            if stale.name not in current:
                stale.unlink()
    for index, (name, caption) in enumerate(SHOTS, 1):
        if only and name not in only:
            continue
        with Image.open(found[name]) as shot:
            (inset if name in INSET else overlay)(shot, caption).save(args.out / f"{index:02d}-{name}.png")
    print(f"{args.out}: {len(only) if only else len(SHOTS)} screenshots")


main()
