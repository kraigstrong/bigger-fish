#!/usr/bin/env python3
"""Composes the Bigger Fish trailer from recorded footage, captions and the game's music.

    python3 scripts/trailer/compose.py <edl.json> <footage folder> <captions folder> <out.mp4> --site|--store
        [--fps 30] [--preview <seconds>]

The EDL (edl.json) lists shots on a 60 fps timeline. Each is a stretch of a recording (scripts/bigger-fish-footage.sh,
named <world>.<level>-<policy>-<from>-<to>) with a slow camera move: zoom, and the centre in fractions of the frame
from the top left, eased from start to end. Captions (captions.py) show between two times, fading and popping in;
"only" keeps one to the site's cut or the App Store's. Frames are moved and composed here, then encoded with the music.
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

W, H, FPS = 1920, 886, 60
SW, SH = 2622, 1206


def frames_of(path, start, count):
    """Decoded RGB frames of a footage file, from `start` seconds."""
    proc = subprocess.Popen(['ffmpeg', '-v', 'error', '-ss', f'{start:.4f}', '-i', path, '-frames:v', str(count),
                             '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdout=subprocess.PIPE)
    size = SW * SH * 3
    for _ in range(count):
        data = proc.stdout.read(size)
        if len(data) < size:
            break
        yield Image.frombuffer('RGB', (SW, SH), data, 'raw', 'RGB', 0, 1)
    proc.stdout.close()
    if proc.wait() != 0:
        sys.exit(f'ffmpeg could not decode {path}')


def ease(u):
    return u * u * (3 - 2 * u)


def framed(image, zoom, cx, cy):
    """The source frame seen through a camera zoomed `zoom` times about (cx, cy), in source fractions, at W x H."""
    vw, vh = SW / zoom, SH / zoom
    x0 = min(max(cx * SW - vw / 2, 0), SW - vw)
    y0 = min(max(cy * SH - vh / 2, 0), SH - vh)
    return image.transform((W, H), Image.EXTENT, (x0, y0, x0 + vw, y0 + vh), Image.BICUBIC)


def main():
    edl_path, footage, caption_dir, out = sys.argv[1:5]
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    variant = 'store' if '--store' in sys.argv else 'site'
    preview = float(sys.argv[sys.argv.index('--preview') + 1]) if '--preview' in sys.argv else None
    out_fps = int(sys.argv[sys.argv.index('--fps') + 1]) if '--fps' in sys.argv else FPS
    edl = json.load(open(edl_path))
    for shot in edl['shots']:
        shot['src'] = os.path.join(footage, shot['footage'] + '.mp4')
    total = edl['duration']
    captions = []
    for c in edl['captions']:
        if c.get('only') and c['only'] != variant:
            continue
        png = Image.open(os.path.join(caption_dir, c['caption'] + '.png')).convert('RGBA')
        captions.append((png, c['in'], c['out'], c.get('fade', 0.12), c.get('pop', True)))

    music = dict(edl['music'], path=os.path.join(root, edl['music']['path']))
    enc = subprocess.Popen(
        ['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
         '-ss', f"{music['offset']:.3f}", '-i', music['path'],
         '-filter_complex', f"[1:a]atrim=0:{total:.3f},afade=t=in:d={music.get('fade_in', 0.05)},"
                            f"afade=t=out:st={total - music['fade_out']:.3f}:d={music['fade_out']:.3f},volume={music.get('gain', 1.0)}[a]",
         '-map', '0:v', '-map', '[a]', '-r', str(out_fps), '-c:v', 'libx264', '-preset', 'slow',
         '-crf', str(edl.get('crf', 18)),
         '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-movflags', '+faststart',
         '-t', f'{total:.3f}', out], stdin=subprocess.PIPE)

    written = 0
    limit = round((preview or total) * FPS)
    for shot in edl['shots']:
        n = round(shot['dur'] * FPS)
        z0, z1 = shot.get('zoom', [1, 1])
        c0, c1 = shot.get('center', [[0.5, 0.5], [0.5, 0.5]])
        def padded():
            # A short source holds its last frame rather than let the cuts drift off the beat.
            last, got = None, 0
            for image in frames_of(shot['src'], shot['in'], n):
                last, got = image, got + 1
                yield image
            if got < n:
                print(f"short shot {shot['src']} at {shot['in']}: {got} of {n} frames", file=sys.stderr)
            for _ in range(n - got):
                yield last
        for i, image in enumerate(padded()):
            u = ease(i / max(n - 1, 1))
            frame = framed(image, z0 + (z1 - z0) * u, c0[0] + (c1[0] - c0[0]) * u, c0[1] + (c1[1] - c0[1]) * u)
            if shot.get('end_card'):
                # Softened and darkened behind the wordmark, coming on over the first half second.
                k = min(1, i / (0.5 * FPS))
                soft = frame.filter(ImageFilter.GaussianBlur(14 * k))
                frame = Image.blend(frame, soft, k)
                frame = Image.blend(frame, Image.new('RGB', (W, H), (6, 18, 44)), 0.45 * k)
            t = (written + 0.5) / FPS
            frame = frame.convert('RGBA')
            for png, t_in, t_out, fade, pop in captions:
                if not (t_in <= t < t_out):
                    continue
                a = min(1, (t - t_in) / fade, (t_out - t) / fade) if fade > 0 else 1
                layer = png
                if pop and t - t_in < 0.25:
                    s = 1.06 - 0.06 * ease((t - t_in) / 0.25)
                    layer = png.resize((round(W * s), round(H * s)), Image.BICUBIC)
                    layer = layer.crop(((layer.width - W) // 2, (layer.height - H) // 2,
                                        (layer.width - W) // 2 + W, (layer.height - H) // 2 + H))
                if a < 1:
                    alpha = np.asarray(layer.split()[3], dtype=np.float32) * a
                    layer = layer.copy()
                    layer.putalpha(Image.fromarray(alpha.astype(np.uint8)))
                frame.alpha_composite(layer)
            if shot.get('flash_in') and i < shot['flash_in'] * FPS:
                k = 1 - i / (shot['flash_in'] * FPS)
                frame = Image.blend(frame, Image.new('RGBA', (W, H), (255, 255, 255, 255)), 0.55 * k)
            enc.stdin.write(frame.convert('RGB').tobytes())
            written += 1
            if written >= limit:
                break
        if written >= limit:
            break
    enc.stdin.close()
    if enc.wait() != 0:
        sys.exit(f'ffmpeg could not encode {out}')
    print(f'{out}: {written} frames, {written / FPS:.2f}s')


main()
