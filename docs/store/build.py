#!/usr/bin/env python3
"""Composes store screenshots from raw simulator captures.

Usage: python3 docs/store/build.py <captures_dir> [out_dir]

Captures are named `<locale>_<screen>.png` (iPhone 17 Pro Max, 1320×2868).
Output: `ios-6.9/<locale>/0N_<screen>.png` (1320×2868, App Store 6.9″;
App Store Connect scales it for smaller displays) and `android/<locale>/…`
(1080×2340, Google Play phone). Fonts: Onest from features_shared.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / 'packages/features/shared/assets/fonts'
SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).parent

BG = (12, 17, 23)
TEXT = (232, 238, 244)
MUTED = (138, 154, 171)
ACCENT = (242, 185, 74)
LINE = (36, 48, 64)

CAPTIONS = {
    'ru': [
        ('markets', 'Живые котировки', 'Топ-20 пар по обороту, одна WebSocket-сессия'),
        ('pair', 'График, стакан, лента', 'Свечи на CustomPainter: зум, панорама, кроссхейр'),
        ('portfolio', 'Портфель вживую', 'Оценка на каждом тике, офлайн по последней цене'),
        ('settings', 'Ничего лишнего', 'Источник данных, язык, тёмная и светлая темы'),
    ],
    'en': [
        ('markets', 'Live quotes', 'Top 20 pairs by turnover over one WebSocket'),
        ('pair', 'Chart, order book, tape', 'CustomPainter candles: zoom, pan, crosshair'),
        ('portfolio', 'Portfolio, valued live', 'Every tick, and offline on the last price'),
        ('settings', 'Nothing extra', 'Data source, language, dark and light themes'),
    ],
}

SIZES = {'ios-6.9': (1320, 2868), 'android': (1080, 2340)}


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    out = im.convert('RGBA')
    out.putalpha(mask)
    return out


def frame(capture: Image.Image, title: str, subtitle: str, size: tuple[int, int]) -> Image.Image:
    w, h = size
    canvas = Image.new('RGB', size, BG)
    draw = ImageDraw.Draw(canvas)
    scale = w / 1320
    title_font = ImageFont.truetype(str(FONTS / 'Onest-SemiBold.ttf'), int(96 * scale))
    sub_font = ImageFont.truetype(str(FONTS / 'Onest-Regular.ttf'), int(46 * scale))

    # Lens ring mark, top-left.
    margin = int(96 * scale)
    r = int(30 * scale)
    cx, cy = margin + r, int(150 * scale)
    draw.arc((cx - r, cy - r, cx + r, cy + r), start=-20, end=270, fill=ACCENT, width=int(7 * scale))
    draw.ellipse((cx - r * 0.34, cy - r * 0.34, cx + r * 0.34, cy + r * 0.34), fill=ACCENT)
    draw.text((cx + r + int(24 * scale), cy), 'TradeLens', font=sub_font, fill=MUTED, anchor='lm')

    draw.text((margin, int(260 * scale)), title, font=title_font, fill=TEXT)
    draw.text((margin, int(390 * scale)), subtitle, font=sub_font, fill=MUTED)

    # Phone capture: status bar cropped, rounded, bleeding off the bottom.
    shot = capture.crop((0, 190, capture.width, capture.height))
    target_w = int(w - 2 * margin)
    shot = shot.resize((target_w, int(shot.height * target_w / shot.width)), Image.LANCZOS)
    shot = rounded(shot, int(72 * scale))
    top = int(520 * scale)
    border = Image.new('RGBA', (shot.width + 4, shot.height + 4), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((0, 0, shot.width + 3, shot.height + 3), int(74 * scale), outline=LINE, width=2)
    canvas.paste(shot, (margin, top), shot)
    canvas.paste(border, (margin - 2, top - 2), border)
    return canvas


def main() -> None:
    for kind, size in SIZES.items():
        for loc, items in CAPTIONS.items():
            out_dir = OUT / kind / loc
            out_dir.mkdir(parents=True, exist_ok=True)
            for i, (screen, title, sub) in enumerate(items, 1):
                src = SRC / f'{loc}_{screen}.png'
                if not src.exists():
                    print('missing', src)
                    continue
                img = frame(Image.open(src).convert('RGB'), title, sub, size)
                img.save(out_dir / f'{i:02d}_{screen}.png', optimize=True)
    print('done', OUT)


if __name__ == '__main__':
    main()
