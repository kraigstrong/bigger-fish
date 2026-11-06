#!/usr/bin/env python3
"""Makes Math Reef's App Store creative assets: the search results image and the product page header.

    scripts/store-creative.py <frame.png> <out.png> [--center 0.5] [--tagline "Swim into the right answer"]
    scripts/store-creative.py <frame.png> <out.png> [--center 0.5] --scale 0.7 --focus 0.45,0.32 [--phone look.png]

The frame is a round drawn big enough for it (STORE_CAPTURE_SCALE=2.2348 scripts/store-capture.sh screenshots play, on
the 6.9" iPhone, draws frames 6409 x 2950). It's cropped to 16:9 at 5244 x 2950, with `--center` (a fraction of the
frame's width) in the middle. Apple asks for one clear idea with the focal point centered, a short phrase at most, no
price or URL, and no alpha (developer.apple.com/app-store/asset-best-practices/).

Search results show all of it, so they take it full size, with the tagline in the water below, inside the 21:9 band
every crop keeps (--tagline "" leaves it out).

The product page header takes `--scale`: an iPhone shows only part of it (PHONE), with the status bar's blur and the
back and share buttons over its top, so the round is drawn smaller and placed with `--focus` (the middle of its
question, its fish, and its answers, as fractions of the crop) in the clear water below them, in its own water carried
on all around. Kraig's first look at the header had "7 x" under the back button and the wrong answer under the blur.
The header has no tagline: an iPhone wouldn't show it, and the app's name is right below. `--phone` saves what an
iPhone shows, with the buttons and the blur marked, to check it before uploading.
"""
import argparse
import math
import random
import statistics

from PIL import Image, ImageChops, ImageCms, ImageDraw, ImageFilter, ImageFont

W, H = 5244, 2950
FONT = ("/System/Library/Fonts/Avenir Next.ttc", 8)  # Avenir Next Heavy, as in the app
BAND = round(W * 9 / 21)  # the 21:9 band every crop keeps, centered
# Where the water below the round darkens toward: ReefScreen.waterBottom at the iPad bands' edge brightness
# (ReefTuning.bandBrightness), as an iPad draws the water below a round.
DEEP = (2, 9, 23)
# What an iPhone shows of the header, measured on App Store Connect's preview (October 2026), in the image's pixels: the
# middle 53% of its width and its top 62%, with the status bar's blur over the top 420 pixels and the back and share
# buttons over its top corners down to 780. A header's focus goes in the clear water between, at PHONE_SPOT.
PHONE = (1227, 0, 4017, 1840)
PHONE_BLUR = 420
PHONE_BUTTONS = [(1334, 428, 1673, 780), (3567, 428, 3906, 780)]
PHONE_SPOT = (W // 2, 1268)


def header(image, scale, focus):
    """The round drawn at `scale`, with `focus` (fractions of it) at PHONE_SPOT, its water carried on all around: as at
    its surface above, and darker below, into the deep."""
    pixels = image.load()
    edges = list(range(0, 300, 3)) + list(range(W - 300, W, 3))  # open water at the sides
    column = Image.new("RGB", (1, H))
    for y in range(H):
        column.putpixel((0, y), tuple(round(statistics.median(pixels[x, y][i] for x in edges)) for i in range(3)))
    sw, sh = round(W * scale), round(H * scale)
    left, top = PHONE_SPOT[0] - round(focus[0] * sw), PHONE_SPOT[1] - round(focus[1] * sh)
    scaled = column.resize((1, sh), Image.LANCZOS)
    surface, bottom = scaled.getpixel((0, 0)), scaled.getpixel((0, sh - 1))
    water = Image.new("RGB", (1, H))
    for y in range(H):
        if y < top:
            water.putpixel((0, y), surface)
        elif y < top + sh:
            water.putpixel((0, y), scaled.getpixel((0, y - top)))
        else:
            t = math.exp(-(y - top - sh) / scale / 1100)
            water.putpixel((0, y), tuple(round(DEEP[i] + (bottom[i] - DEEP[i]) * t) for i in range(3)))
    canvas = water.resize((W, H), Image.NEAREST).convert("RGBA")

    # Specks in the new water, like the game's: crisp white dots, about a third opaque, a little dimmer in the deep.
    rng, k = random.Random(7), 2
    specks = Image.new("RGBA", (W * k, H * k))
    draw = ImageDraw.Draw(specks)
    placed = 0
    while placed < 60:
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        if left + 40 < x < left + sw - 40 and top + 40 < y < top + sh - 40:
            continue
        r, a = rng.uniform(9, 13) * scale, rng.uniform(0.25, 0.35) * (0.8 if y > top + sh else 1)
        draw.ellipse(((x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k), fill=(255, 255, 255, round(a * 255)))
        placed += 1
    canvas.alpha_composite(specks.resize((W, H), Image.LANCZOS))

    # The round, feathered into that water on every side.
    feather = 160
    ramp = Image.linear_gradient("L").rotate(90).resize((feather, sh))
    mask = Image.new("L", (sw, sh), 255)
    mask.paste(ramp, (0, 0))
    mask.paste(ramp.transpose(Image.FLIP_LEFT_RIGHT), (sw - feather, 0))
    drop = Image.linear_gradient("L").resize((sw, feather))
    fade = Image.new("L", (sw, sh), 255)
    fade.paste(drop, (0, 0))
    fade.paste(drop.transpose(Image.FLIP_TOP_BOTTOM), (0, sh - feather))
    canvas.paste(image.resize((sw, sh), Image.LANCZOS).convert("RGBA"), (left, top), ImageChops.multiply(mask, fade))
    return canvas.convert("RGB")


def phone_view(image):
    """What an iPhone shows of a header, with the blur and the buttons shaded where they go."""
    view = image.crop(PHONE).convert("RGBA")
    marks = Image.new("RGBA", view.size)
    draw = ImageDraw.Draw(marks)
    draw.rectangle((0, 0, view.width, PHONE_BLUR), fill=(255, 255, 255, 90))
    for x0, y0, x1, y1 in PHONE_BUTTONS:
        draw.ellipse((x0 - PHONE[0], y0, x1 - PHONE[0], y1), fill=(255, 255, 255, 160))
    view.alpha_composite(marks)
    return view.convert("RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("frame")
    parser.add_argument("out")
    parser.add_argument("--center", type=float, default=0.5, help="the crop's middle, as a fraction of the width")
    parser.add_argument("--scale", type=float, default=1, help="below 1, the header: the round drawn that much smaller")
    parser.add_argument("--focus", default="0.5,0.5", help="the header's x,y focus, as fractions of the crop")
    parser.add_argument("--tagline", default="Swim into the right answer", help="search results only")
    parser.add_argument("--phone", help="also save what an iPhone shows of the header here")
    args = parser.parse_args()

    frame = Image.open(args.frame).convert("RGB")
    if frame.height < H or frame.width < W:
        raise SystemExit(f"{args.frame} is {frame.width}x{frame.height}; capture it at STORE_CAPTURE_SCALE=2.2348 for {W}x{H}")
    left = min(max(round(args.center * frame.width - W / 2), 0), frame.width - W)
    top = (frame.height - H) // 2
    image = frame.crop((left, top, left + W, top + H))

    if args.scale < 1:
        focus = tuple(float(f) for f in args.focus.split(","))
        image = header(image, args.scale, focus)
        if args.phone:
            phone_view(image).save(args.phone)
            print(f"{args.phone}: what an iPhone shows")
    elif args.tagline:
        font = ImageFont.truetype(FONT[0], 250, index=FONT[1])
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        box = draw.textbbox((0, 0), args.tagline, font=font)
        band_bottom = (H - BAND) // 2 + BAND
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
