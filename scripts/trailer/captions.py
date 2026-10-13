#!/usr/bin/env python3
"""The trailer's words, as transparent 1920x886 PNGs in the game's typeface (Avenir Next), for compose.py.

    python3 scripts/trailer/captions.py <out folder>

Each beat and world caption sits over a soft dark band up the bottom of the frame, so it reads over busy water.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1920, 886
FONT = '/System/Library/Fonts/Avenir Next.ttc'
HEAVY, DEMI = 8, 2  # faces in the collection
WHITE = (255, 255, 255, 255)
GOLD = (255, 211, 77, 255)

# The end card's last line on biggerfish.app. The App Store preview leaves it off: no dates there.
RELEASE_LINE = 'Coming to iPhone and iPad November 3'

BEATS = [('eat', 'EAT.'), ('grow', 'GROW.'), ('they-grow-too', 'THEY GROW TOO.'), ('win-the-food-race', 'WIN THE FOOD RACE.'),
         ('turn-the-tables', 'TURN THE TABLES.'), ('five-worlds', 'FIVE WORLDS. 75 LEVELS.')]
# Each world's name in its map color (`ArcadeWorld.mapColor`), its motto (`ArcadeWorld.subtitle`) under it.
WORLDS = [
    ('jelly-bloom', 'Jelly Bloom', 'Bounce the tops. Dodge the tentacles.', (191, 133, 255)),
    ('kelp-forest', 'Kelp Forest', "Dive into the kelp. Mind what's hiding.", (115, 199, 82)),
    ('sunset-cove', 'Sunset Cove', 'Watch the boats. Leave the bait.', (255, 128, 143)),
    ('midnight-zone', 'Midnight Zone', 'Light the way. Mind the dark.', (255, 168, 77)),
]


def font(face, size):
    return ImageFont.truetype(FONT, size, index=face)


def shadowed(text_layer, blur=14, opacity=170):
    """The text over a soft dark shadow of itself."""
    shadow = Image.new('RGBA', text_layer.size, (8, 14, 40, 0))
    shadow.putalpha(text_layer.split()[3].point(lambda a: a * opacity // 255))
    out = Image.new('RGBA', text_layer.size, (0, 0, 0, 0))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)), (0, 6))
    out.alpha_composite(text_layer)
    return out


def band(height=300, strength=0.5):
    """A soft dark band up the bottom of the frame."""
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ramp = Image.linear_gradient('L').resize((W, height)).point(lambda v: int(v * strength * v / 255))
    tint = Image.new('RGBA', (W, height), (4, 12, 34, 0))
    tint.putalpha(ramp)
    layer.alpha_composite(tint, (0, H - height))
    return layer


def centred(draw, rows, top, gap):
    """Draws (text, face, size, color) rows centred from `top`; returns where the last one ends."""
    y = top
    for text, face, size, color in rows:
        box = draw.textbbox((0, 0), text, font=font(face, size))
        draw.text(((W - (box[2] - box[0])) / 2 - box[0], y - box[1]), text, font=font(face, size), fill=color)
        y += box[3] - box[1] + gap
    return y - gap


def caption(rows, bottom=H - 66, gap=16):
    """Rows of text centred above `bottom`, over the band."""
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    heights = [draw.textbbox((0, 0), t, font=font(f, s)) for t, f, s, _ in rows]
    total = sum(b[3] - b[1] for b in heights) + gap * (len(rows) - 1)
    centred(draw, rows, bottom - total, gap)
    out = band()
    out.alpha_composite(shadowed(layer))
    return out


def end_card(release_line):
    """The wordmark, the tagline, and the release line if there is one."""
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rows = [('Bigger Fish', HEAVY, 206, WHITE), ('Eat fast. Stay alive.', DEMI, 66, WHITE)]
    if release_line:
        rows.append((release_line, HEAVY, 58, GOLD))
    # Centred on the frame as a block, the wordmark a little further from the lines under it.
    heights = [draw.textbbox((0, 0), t, font=font(f, s)) for t, f, s, _ in rows]
    total = sum(b[3] - b[1] for b in heights) + 56 + 34 * (len(rows) - 2)
    y = (H - total) / 2
    y = centred(draw, rows[:1], y, 0) + 56
    centred(draw, rows[1:], y, 34)
    return shadowed(layer, blur=18, opacity=150)


def end_lockup():
    """The App Store preview's end card: the wordmark and tagline low in the frame, under a bite sharp enough to be
    the preview's poster frame (the still the App Store shows until it plays)."""
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rows = [('Bigger Fish', HEAVY, 150, WHITE), ('Eat fast. Stay alive.', DEMI, 52, WHITE)]
    heights = [draw.textbbox((0, 0), t, font=font(f, s)) for t, f, s, _ in rows]
    centred(draw, rows, H - 44 - sum(b[3] - b[1] for b in heights) - 30, 30)
    return shadowed(layer, blur=18, opacity=150)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, text in BEATS:
        caption([(text, HEAVY, 104 if name != 'five-worlds' else 92, WHITE)]).save(os.path.join(out, name + '.png'))
    for slug, title, motto, color in WORLDS:
        caption([(title.upper(), HEAVY, 92, color + (255,)), (motto, DEMI, 42, WHITE)]).save(
            os.path.join(out, 'world-' + slug + '.png'))
    end_card(RELEASE_LINE).save(os.path.join(out, 'end-site.png'))
    end_lockup().save(os.path.join(out, 'end-store.png'))


main()
