#!/usr/bin/env python3
"""Turns simulator frames into the README demo GIF.

Usage: python3 docs/demo/build.py <frames_dir> [out.gif] [first.png] [last.png]

The frames come from `tooling/scripts/record_demo.sh`, which grabs them
while a Patrol scenario drives the app and names the first and the last
one that belong to the run. The window still opens on the home screen —
the app has a process before it has a first frame — and the runner's own
near-blank "Test starting..." screen always follows it, so the demo is
what comes after the first blank frame, minus every other blank one.

The top of every frame goes too: the status bar, and under it the test
description the live-test binding paints over the app in red.

What is left is not a constant frame rate, so the GIF gets one: frames
that look the same collapse into one long-held frame, the rest play at
`FPS`.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

FPS = 8
WIDTH = 360           # a phone-sized figure in a README column
TOP = 0.088           # cropped away: the status bar and the test label
SAME = 0.15           # mean channel difference counted as "no change"
BLANK = 18            # contrast below this is a screen with nothing on it
MAX_HOLD_MS = 1400    # how long one unchanged frame may stay on screen
COLORS = 128          # the palette; the UI is flat, so this is generous


def load(path: Path) -> Image.Image:
    im = Image.open(path).convert('RGB')
    im = im.crop((0, round(im.height * TOP), im.width, im.height))
    return im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)


def difference(a: Image.Image, b: Image.Image) -> float:
    """Mean per-channel difference, 0 for identical frames."""
    return ImageStat.Stat(ImageChops.difference(a, b)).mean[0]


def demo(src: Path, first: str, last: str) -> list[Image.Image]:
    files = [f for f in sorted(src.glob('*.png'))
             if (not first or f.name >= first) and (not last or f.name <= last)]
    if not files:
        sys.exit(f'no frames in {src} between {first!r} and {last!r}')
    out = [load(f) for f in files]
    blank = [ImageStat.Stat(im.convert('L')).stddev[0] < BLANK for im in out]
    start = blank.index(True) if True in blank else 0
    out = [im for im, b in zip(out[start:], blank[start:]) if not b]
    if not out:
        sys.exit(f'every frame in {src} was the runner\'s own screen')
    return out


def collapse(ims: list[Image.Image]) -> tuple[list[Image.Image], list[int]]:
    """One entry per visible state, with how long it stays on screen."""
    step = round(1000 / FPS)
    keep, hold = [ims[0]], [step]
    for im in ims[1:]:
        if difference(keep[-1], im) > SAME:
            keep.append(im)
            hold.append(step)
        else:
            hold[-1] = min(hold[-1] + step, MAX_HOLD_MS)
    return keep, hold


def main() -> None:
    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).parent / 'tradelens.gif'
    first = sys.argv[3] if len(sys.argv) > 3 else ''
    last = sys.argv[4] if len(sys.argv) > 4 else ''
    keep, hold = collapse(demo(src, first, last))
    keep = [im.quantize(colors=COLORS, method=Image.MEDIANCUT) for im in keep]
    keep[0].save(
        out,
        save_all=True,
        append_images=keep[1:],
        duration=hold,
        loop=0,
        optimize=True,
        disposal=1,
    )
    print(
        f'{out}: {len(keep)} frames, {sum(hold) / 1000:.0f}s, '
        f'{out.stat().st_size / 1024 / 1024:.1f} MB'
    )


if __name__ == '__main__':
    main()
