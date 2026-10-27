#!/usr/bin/env python3
"""Makes Math Reef's universal creative: the App Store's product page header and search results image.

    scripts/store-creative.py <frame.png> <out.png> [--center 0.5] [--scale 1] [--tagline "Swim into the right answer"]

The frame is a round drawn big enough for it (STORE_CAPTURE_SCALE=2.2348 scripts/store-capture.sh screenshots play, on
the 6.9" iPhone, draws frames 6409 x 2950). It's cropped to 16:9 at 5244 x 2950, with `--center` (a fraction of the
frame's width) in the middle, and the tagline in the water below, inside the 21:9 band every header crop keeps. Apple
asks for one clear idea with the focal point centered, a short phrase at most, no price or URL, and no alpha
(developer.apple.com/app-store/asset-best-practices/). The tagline can be left out with --tagline "".

The product page header needs `--scale 0.7`, as Bigger Fish's does (scripts/bigger-fish-creative.py): on an iPhone it
shows only the middle half of the image's width and its top 60% or so (the title card covers the rest), so at full size
it would be a close-up of one fish. Scaled, the round sits at the top of the image, smaller, with the water carried on
around it and darker below, as on an iPad, and the iPhone's crop holds the whole question. Search results show all of
it, so they take the full-size version.
"""
import argparse
import math
import random
import statistics

from PIL import Image, ImageChops, ImageCms, ImageDraw, ImageFilter, ImageFont

W, H = 5244, 2950
FONT = ("/System/Library/Fonts/Avenir Next.ttc", 8)  # Avenir Next Heavy, as in the app
BAND = round(W * 9 / 21)  # the 21:9 band every header crop keeps, centered
# Where the water below the round darkens toward: ReefScreen.waterBottom at the iPad bands' edge brightness
# (ReefTuning.bandBrightness), as an iPad draws the water below a round.
DEEP = (2, 9, 23)


def smaller(image, scale):
    """The round drawn at `scale`, at the top, with its water carried on to the sides and down into the deep."""
    pixels = image.load()
    edges = list(range(0, 300, 3)) + list(range(W - 300, W, 3))  # open water at the sides
    column = Image.new("RGB", (1, H))
    for y in range(H):
        column.putpixel((0, y), tuple(round(statistics.median(pixels[x, y][i] for x in edges)) for i in range(3)))
    sw, sh = round(W * scale), round(H * scale)
    water = Image.new("RGB", (1, H))
    water.paste(column.resize((1, sh), Image.LANCZOS), (0, 0))
    bottom = column.getpixel((0, H - 1))
    for y in range(sh, H):
        t = math.exp(-(y - sh) / scale / 1100)
        water.putpixel((0, y), tuple(round(DEEP[i] + (bottom[i] - DEEP[i]) * t) for i in range(3)))
    canvas = water.resize((W, H), Image.NEAREST).convert("RGBA")

    # Specks in the new water, like the game's: crisp white dots, about a third opaque, a little dimmer in the deep.
    left, rng, k = (W - sw) // 2, random.Random(7), 2
    specks = Image.new("RGBA", (W * k, H * k))
    draw = ImageDraw.Draw(specks)
    placed = 0
    while placed < 60:
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        if left + 40 < x < left + sw - 40 and y < sh - 40:
            continue
        r, a = rng.uniform(9, 13) * scale, rng.uniform(0.25, 0.35) * (0.8 if y > sh else 1)
        draw.ellipse(((x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k), fill=(255, 255, 255, round(a * 255)))
        placed += 1
    canvas.alpha_composite(specks.resize((W, H), Image.LANCZOS))

    # The round, feathered into that water on its sides and bottom (its surface stays at the top).
    feather = 160
    ramp = Image.linear_gradient("L").rotate(90).resize((feather, sh))
    mask = Image.new("L", (sw, sh), 255)
    mask.paste(ramp, (0, 0))
    mask.paste(ramp.transpose(Image.FLIP_LEFT_RIGHT), (sw - feather, 0))
    fade = Image.new("L", (sw, sh), 255)
    fade.paste(Image.linear_gradient("L").rotate(180).resize((sw, feather)), (0, sh - feather))
    canvas.paste(image.resize((sw, sh), Image.LANCZOS).convert("RGBA"), (left, 0), ImageChops.multiply(mask, fade))
    return canvas.convert("RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("frame")
    parser.add_argument("out")
    parser.add_argument("--center", type=float, default=0.5, help="the crop's middle, as a fraction of the width")
    parser.add_argument("--scale", type=float, default=1, help="draw the round smaller (0.7 for the header)")
    parser.add_argument("--tagline", default="Swim into the right answer")
    args = parser.parse_args()

    frame = Image.open(args.frame).convert("RGB")
    if frame.height < H or frame.width < W:
        raise SystemExit(f"{args.frame} is {frame.width}x{frame.height}; capture it at STORE_CAPTURE_SCALE=2.2348 for {W}x{H}")
    left = min(max(round(args.center * frame.width - W / 2), 0), frame.width - W)
    top = (frame.height - H) // 2
    image = frame.crop((left, top, left + W, top + H))
    if args.scale < 1:
        image = smaller(image, args.scale)

    if args.tagline:
        font = ImageFont.truetype(FONT[0], 250, index=FONT[1])
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        box = draw.textbbox((0, 0), args.tagline, font=font)
        band_bottom = (H - BAND) // 2 + BAND
        if args.scale < 1:
            # Centered in the deep water between the round and the bottom of the band, below the iPhone's crop.
            y = (round(H * args.scale) + band_bottom - (box[3] - box[1])) // 2
        else:
            # Its baseline 170 pixels above the bottom of the band.
            y = band_bottom - (box[3] - box[1]) - 170
        draw.text(((W - (box[2] - box[0])) / 2 - box[0], y - box[1]), args.tagline, font=font, fill=(255, 255, 255, 255))
        shadow = Image.new("RGBA", (W, H), (8, 14, 40, 0))
        shadow.putalpha(layer.split()[3].point(lambda a: a * 160 // 255))
        composed = image.convert("RGBA")
        composed.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(26)), (0, 12))
        composed.alpha_composite(layer)
        image = composed.convert("RGB")

    srgb = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    image.save(args.out, icc_profile=srgb, optimize=True)
    print(f"{args.out}: {W}x{H}, no alpha, sRGB")


main()
