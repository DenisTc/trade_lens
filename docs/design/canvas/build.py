#!/usr/bin/env python3
"""Generates the TradeLens design-canvas artboards (.dc.html) + canvas.json.

Usage: python3 build.py <out_dir> <fontface.css>
fontface.css holds embedded @font-face rules for Onest + IBM Plex Mono
(latin + cyrillic subsets); see docs/design/brief.md.
"""
import json, math, random, sys
from pathlib import Path

OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
FONTS = Path(sys.argv[2]).read_text()

DARK = dict(bg='#0C1117', surface='#121922', raised='#1A2330', line='#243040',
            text='#E8EEF4', muted='#8A9AAB', accent='#F2B94A', up='#3DDC97',
            down='#FF6B5E', onaccent='#14110A', upbg='rgba(61,220,151,0.12)',
            downbg='rgba(255,107,94,0.12)', accbg='rgba(242,185,74,0.14)',
            glass='rgba(18,25,34,0.55)', glassline='rgba(255,255,255,0.12)', glasshi='rgba(255,255,255,0.10)', shadow='rgba(0,0,0,0.45)')
LIGHT = dict(bg='#F2F5FA', surface='#FFFFFF', raised='#E5EBF5', line='#D3DCEA',
             text='#0F172A', muted='#5B6B82', accent='#C7880E', up='#12925C',
             down='#D64545', onaccent='#FFFFFF', upbg='rgba(18,146,92,0.12)',
             downbg='rgba(214,69,69,0.12)', accbg='rgba(199,136,14,0.14)',
             glass='rgba(255,255,255,0.62)', glassline='rgba(15,23,42,0.10)', glasshi='rgba(255,255,255,0.9)', shadow='rgba(15,23,42,0.14)')
NEON = dict(bg='#07070C', surface='#0F0F18', raised='#171726', line='#232338',
            text='#F2F2FF', muted='#7E7E9A', accent='#00E5FF', up='#3DF5A0',
            down='#FF2E88', onaccent='#06060A', upbg='rgba(61,245,160,0.14)',
            downbg='rgba(255,46,136,0.14)', accbg='rgba(0,229,255,0.14)',
            glass='rgba(15,15,26,0.55)', glassline='rgba(0,229,255,0.22)', glasshi='rgba(255,255,255,0.10)', shadow='rgba(0,229,255,0.18)')

SANS = "'Onest', 'Avenir Next', 'Helvetica Neue', system-ui, sans-serif"
MONO = "'IBM Plex Mono', 'SF Mono', Menlo, monospace"

def fmt(n, dec=2):
    s = f"{n:,.{dec}f}".replace(',', ' ').replace('.', ',')
    return s

def walk(seed, n, start, vol):
    r = random.Random(seed); xs = [start]
    for _ in range(n - 1):
        xs.append(xs[-1] * (1 + r.gauss(0, vol)))
    return xs

# ---------- SVG helpers ----------
def ring(size=24, color='#F2B94A', inner=True, gap=True):
    r = size * 0.38; c = size / 2; sw = max(1.5, size * 0.085)
    circ = 2 * math.pi * r
    dash = f' stroke-dasharray="{circ*0.82:.1f} {circ*0.18:.1f}" stroke-linecap="round" transform="rotate(-50 {c} {c})"' if gap else ''
    dot = f'<circle cx="{c}" cy="{c}" r="{size*0.13:.1f}" fill="{color}"></circle>' if inner else ''
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" fill="none">'
            f'<circle cx="{c}" cy="{c}" r="{r:.1f}" stroke="{color}" stroke-width="{sw:.1f}"{dash}></circle>{dot}</svg>')

def icon(name, color, size=24):
    p = {
      'search': '<circle cx="11" cy="11" r="7"></circle><path d="M20 20l-3.5-3.5"></path>',
      'back': '<path d="M15 5l-7 7 7 7"></path>',
      'chevron': '<path d="M9 5l7 7-7 7"></path>',
      'markets': '<path d="M7 4v4M7 16v4M17 6v3M17 15v3"></path><rect x="4.5" y="8" width="5" height="8" rx="1"></rect><rect x="14.5" y="9" width="5" height="6" rx="1"></rect>',
      'portfolio': '<path d="M12 3v9l7.8-4.5"></path><circle cx="12" cy="12" r="9"></circle>',
      'settings': '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"></path><circle cx="16" cy="7" r="2"></circle><circle cx="10" cy="17" r="2"></circle>',
      'source': '<path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18"></path><circle cx="12" cy="12" r="9"></circle>',
      'language': '<path d="M4 5h10M9 3v2M11.5 5c-.7 4-3.5 8-7.5 10M6.5 9c1.5 3 4 5 7 6M13 21l4-10 4 10M14.5 17h5"></path>',
      'about': '<circle cx="12" cy="12" r="9"></circle><path d="M12 11v6M12 7.5v.5"></path>',
      'theme': '<circle cx="12" cy="12" r="9"></circle><path d="M12 3a9 9 0 0 1 0 18z" fill="CURRENT"></path>',
      'link': '<path d="M14 5h5v5M19 5l-8 8M10 6H6a1 1 0 0 0-1 1v11a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1v-4"></path>',
      'check': '<path d="M5 12.5l4.5 4.5L19 7.5"></path>',
      'plus': '<path d="M12 5v14M5 12h14"></path>',
      'star': '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1.1 5.9L12 16.9l-5.3 2.8 1.1-5.9-4.3-4.1 5.9-.8z"></path>',
      'x': '<path d="M6 6l12 12M18 6L6 18"></path>',
    }[name]
    p = p.replace('CURRENT', color)
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{p}</svg>')

def sparkline(vals, color, w=64, h=24, fill_alpha=0.18):
    lo, hi = min(vals), max(vals); rng = (hi - lo) or 1
    pts = [(i * w / (len(vals) - 1), h - 2 - (v - lo) / rng * (h - 4)) for i, v in enumerate(vals)]
    line = ' '.join(f'{x:.1f},{y:.1f}' for x, y in pts)
    area = f'M0,{h} L{line.replace(" ", " L")} L{w},{h} Z'
    return (f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none">'
            f'<path d="{area}" fill="{color}" fill-opacity="{fill_alpha}"></path>'
            f'<polyline points="{line}" stroke="{color}" stroke-width="1.5" stroke-linejoin="round"></polyline></svg>')

# ---------- markup helpers ----------
def html_doc(t, body, title, extra_css=''):
    return f'''<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
    {FONTS}
    body {{ margin: 0; background: {t['bg']}; font-family: {SANS}; color: {t['text']}; -webkit-font-smoothing: antialiased; }}
    a {{ color: {t['accent']}; }} a:hover {{ color: {t['text']}; }}
    .mono {{ font-family: {MONO}; font-variant-numeric: tabular-nums; }}
    {extra_css}
  </style>
</helmet>
{body}
</x-dc>
</body>
</html>
'''

def phone(t, children, pad_top=54):
    return (f'<div style="width: 390px; height: 844px; background: {t["bg"]}; overflow: hidden; '
            f'display: flex; flex-direction: column; box-sizing: border-box; padding-top: {pad_top}px; position: relative;">'
            + ''.join(children) + '</div>')

def tabbar(t, active):
    items = [('markets', 'Рынки'), ('portfolio', 'Портфель'), ('settings', 'Настройки')]
    cells = []
    for key, label in items:
        on = key == active
        col = t['accent'] if on else t['muted']
        cells.append(
            f'<div style="flex-grow: 1; height: 52px; border-radius: 26px; background: {t["accbg"] if on else "transparent"}; '
            f'display: flex; flex-direction: row; align-items: center; justify-content: center; gap: 8px;">'
            f'{icon(key, col, 22)}<span style="font-size: 12px; font-weight: {600 if on else 500}; color: {col};">{label}</span></div>')
    return (f'<div style="position: absolute; left: 16px; right: 16px; bottom: 34px; height: 64px; border-radius: 32px; '
            f'background: {t["glass"]}; -webkit-backdrop-filter: blur(28px) saturate(1.7); backdrop-filter: blur(28px) saturate(1.7); '
            f'border: 1px solid {t["glassline"]}; box-shadow: 0 12px 32px {t["shadow"]}, inset 0 1px 0 {t["glasshi"]}; '
            f'display: flex; flex-direction: row; align-items: center; gap: 4px; padding: 6px; box-sizing: border-box;">'
            + ''.join(cells) + '</div>')

def chip(t, text, kind):
    col = t[kind]; bg = t[kind + 'bg']
    return (f'<span class="mono" style="display: inline-flex; align-items: center; height: 22px; padding: 0 7px; '
            f'border-radius: 6px; background: {bg}; color: {col}; font-size: 12px; font-weight: 500;">{text}</span>')

def status(t, live=True, when='12:41'):
    col = t['up'] if live else t['muted']
    text = 'Онлайн' if live else f'На {when}'
    return (f'<div style="display: flex; flex-direction: row; align-items: center; gap: 6px;">'
            f'{ring(16, col, inner=live, gap=False)}<span style="font-size: 12px; font-weight: 500; color: {col};">{text}</span></div>')

def header(t, left, right):
    return (f'<div style="height: 56px; display: flex; flex-direction: row; align-items: center; justify-content: space-between; '
            f'padding: 0 8px 0 20px; box-sizing: border-box;">{left}<div style="display: flex; flex-direction: row; align-items: center; gap: 4px;">{right}</div></div>')

def wordmark(t):
    return (f'<div style="display: flex; flex-direction: row; align-items: center; gap: 10px;">{ring(26, t["accent"])}'
            f'<span style="font-size: 20px; font-weight: 600; letter-spacing: -0.02em;">TradeLens</span></div>')

def iconbtn(t, name, color=None):
    return (f'<div style="width: 44px; height: 44px; display: flex; align-items: center; justify-content: center; border-radius: 12px;">'
            f'{icon(name, color or t["text"])}</div>')

# ---------- data ----------
PAIRS = [
    ('BTC', 'Bitcoin', 67432.10, 2.14, 11), ('ETH', 'Ethereum', 3518.42, 1.36, 12),
    ('SOL', 'Solana', 172.85, -3.42, 13), ('BNB', 'BNB', 598.30, 0.42, 14),
    ('XRP', 'XRP', 0.5231, -1.08, 15), ('DOGE', 'Dogecoin', 0.1584, 5.87, 16),
    ('ADA', 'Cardano', 0.4412, -0.66, 17), ('AVAX', 'Avalanche', 36.14, 2.91, 18),
    ('TON', 'Toncoin', 7.208, 0.12, 19), ('LINK', 'Chainlink', 14.63, -2.27, 20),
]

def pair_row(t, sym, name, price, chg, seed):
    up = chg >= 0; col = t['up'] if up else t['down']
    vals = walk(seed, 24, 100, 0.02)
    if up != (vals[-1] >= vals[0]): vals = vals[::-1]
    dec = 2 if price >= 10 else 4
    return (f'<div style="height: 64px; display: flex; flex-direction: row; align-items: center; gap: 12px; padding: 0 20px; box-sizing: border-box;">'
            f'<div style="display: flex; flex-direction: column; gap: 3px; width: 108px;">'
            f'<div style="display: flex; flex-direction: row; align-items: baseline; gap: 2px;"><span style="font-size: 16px; font-weight: 600;">{sym}</span>'
            f'<span style="font-size: 13px; color: {t["muted"]};">/USDT</span></div>'
            f'<span style="font-size: 12px; color: {t["muted"]};">{name}</span></div>'
            f'<div style="flex-grow: 1; display: flex; justify-content: center;">{sparkline(vals, col)}</div>'
            f'<div style="display: flex; flex-direction: column; align-items: flex-end; gap: 4px; width: 112px;">'
            f'<span class="mono" style="font-size: 15px; font-weight: 500;">{fmt(price, dec)}</span>'
            f'{chip(t, ("+" if up else "−") + fmt(abs(chg)) + "\u202f%", "up" if up else "down")}</div></div>')

def skeleton_row(t):
    b = t['raised']
    bar = lambda w, h=10: f'<div style="width: {w}px; height: {h}px; border-radius: 5px; background: {b};"></div>'
    return (f'<div style="height: 64px; display: flex; flex-direction: row; align-items: center; gap: 12px; padding: 0 20px; box-sizing: border-box; opacity: 0.9;">'
            f'<div style="display: flex; flex-direction: column; gap: 8px; width: 108px;">{bar(64, 12)}{bar(44)}</div>'
            f'<div style="flex-grow: 1; display: flex; justify-content: center;">{bar(64, 20)}</div>'
            f'<div style="display: flex; flex-direction: column; align-items: flex-end; gap: 8px; width: 112px;">{bar(76, 12)}{bar(52, 18)}</div></div>')

# ---------- screens ----------
def markets(t, light=False):
    rows = ''.join(pair_row(t, *p) for p in PAIRS) + skeleton_row(t) + skeleton_row(t)
    sub = (f'<div style="height: 36px; display: flex; flex-direction: row; align-items: center; justify-content: space-between; '
           f'padding: 0 20px; box-sizing: border-box; border-bottom: 1px solid {t["line"]};">'
           f'<span style="font-size: 12px; font-weight: 500; color: {t["muted"]}; letter-spacing: 0.02em;">Топ-20 по обороту · USDT</span>'
           f'<span style="font-size: 12px; color: {t["muted"]};">Цена · 24 ч</span></div>')
    body = phone(t, [
        header(t, wordmark(t), status(t) + iconbtn(t, 'search')),
        sub,
        f'<div style="flex-grow: 1; overflow: hidden; display: flex; flex-direction: column;">{rows}</div>',
        tabbar(t, 'markets'),
    ])
    return html_doc(t, body, 'Markets')

def candles_svg(t, w=350, h=236, n=40, seed=7, cross=29):
    r = random.Random(seed); o = 66900.0; cs = []
    for i in range(n):
        c = o * (1 + r.gauss(0.0006, 0.006)); hi = max(o, c) * (1 + abs(r.gauss(0, 0.003))); lo = min(o, c) * (1 - abs(r.gauss(0, 0.003)))
        cs.append((o, hi, lo, c, abs(r.gauss(1, 0.4)))); o = c
    lo = min(c[2] for c in cs); hi = max(c[1] for c in cs); pad = (hi - lo) * 0.08; lo -= pad; hi += pad
    axis_w = 58; cw = (w - axis_w) / n; body_w = cw * 0.62
    y = lambda v: (hi - v) / (hi - lo) * h
    parts = []
    for k in range(5):
        gy = h * k / 4; val = hi - (hi - lo) * k / 4
        parts.append(f'<line x1="0" y1="{gy:.1f}" x2="{w-axis_w}" y2="{gy:.1f}" stroke="{t["line"]}" stroke-width="1"></line>')
        ly = min(max(gy + 4, 9), h - 2)
        if abs(gy - y(cs[cross][3])) > 14: parts.append(f'<text x="{w-axis_w+8}" y="{ly:.1f}" font-family="IBM Plex Mono, Menlo, monospace" font-size="10" fill="{t["muted"]}">{fmt(val, 0)}</text>')
    for i, (o_, h_, l_, c_, v_) in enumerate(cs):
        x = i * cw + cw / 2; col = t['up'] if c_ >= o_ else t['down']
        top, bot = y(max(o_, c_)), y(min(o_, c_))
        parts.append(f'<line x1="{x:.1f}" y1="{y(h_):.1f}" x2="{x:.1f}" y2="{y(l_):.1f}" stroke="{col}" stroke-width="1"></line>')
        parts.append(f'<rect x="{x-body_w/2:.1f}" y="{top:.1f}" width="{body_w:.1f}" height="{max(1, bot-top):.1f}" fill="{col}" rx="1"></rect>')
    # crosshair
    cx = cross * cw + cw / 2; cyv = cs[cross][3]; cy = y(cyv)
    parts.append(f'<line x1="{cx:.1f}" y1="0" x2="{cx:.1f}" y2="{h}" stroke="{t["accent"]}" stroke-width="1" stroke-dasharray="3 3"></line>')
    parts.append(f'<line x1="0" y1="{cy:.1f}" x2="{w-axis_w}" y2="{cy:.1f}" stroke="{t["accent"]}" stroke-width="1" stroke-dasharray="3 3"></line>')
    parts.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="6" stroke="{t["accent"]}" stroke-width="1.5" fill="none"></circle>')
    parts.append(f'<rect x="{w-axis_w+2}" y="{cy-10:.1f}" width="{axis_w-2}" height="20" rx="4" fill="{t["accent"]}"></rect>')
    parts.append(f'<text x="{w-axis_w+8}" y="{cy+4:.1f}" font-family="IBM Plex Mono, Menlo, monospace" font-size="10" font-weight="600" fill="{t["onaccent"]}">{fmt(cyv, 0)}</text>')
    chart = f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none" style="display: block;">{"".join(parts)}</svg>'
    # volume
    vh = 36; vmax = max(c[4] for c in cs); vparts = []
    for i, c in enumerate(cs):
        bh = c[4] / vmax * vh; col = t['up'] if c[3] >= c[0] else t['down']
        vparts.append(f'<rect x="{i*cw+cw*0.19:.1f}" y="{vh-bh:.1f}" width="{body_w:.1f}" height="{bh:.1f}" fill="{col}" fill-opacity="0.45" rx="1"></rect>')
    vol = f'<svg width="{w}" height="{vh}" viewBox="0 0 {w} {vh}" fill="none" style="display: block;">{"".join(vparts)}</svg>'
    times = ['09:00', '11:00', '13:00', '15:00', '17:00']
    axis = (f'<div class="mono" style="display: flex; flex-direction: row; justify-content: space-between; width: {w-axis_w}px; font-size: 10px; color: {t["muted"]};">'
            + ''.join(f'<span>{x}</span>' for x in times) + '</div>')
    return chart, vol, axis

def pair(t):
    chart, vol, axis = candles_svg(t)
    pills = []
    for iv in ['1м', '5м', '15м', '1ч', '4ч', '1Д']:
        on = iv == '1ч'
        pills.append(f'<div style="height: 32px; padding: 0 12px; display: flex; align-items: center; border-radius: 16px; '
                     f'border: 1.5px solid {t["accent"] if on else "transparent"}; background: {t["accbg"] if on else "transparent"}; '
                     f'color: {t["accent"] if on else t["muted"]}; font-size: 13px; font-weight: 600;">{iv}</div>')
    book_rows = []
    r = random.Random(3)
    for i in range(7):
        bq = r.uniform(0.2, 4.5); aq = r.uniform(0.2, 4.5)
        bp = 67431.5 - i * 0.7; ap = 67432.1 + i * 0.8
        book_rows.append(
            f'<div class="mono" style="height: 24px; display: flex; flex-direction: row; align-items: center; font-size: 12px;">'
            f'<div style="flex-grow: 1; position: relative; display: flex; justify-content: space-between; padding-right: 8px;">'
            f'<div style="position: absolute; right: 0; top: 2px; bottom: 2px; width: {bq/4.5*100:.0f}%; background: {t["upbg"]}; border-radius: 3px;"></div>'
            f'<span style="position: relative; color: {t["muted"]};">{fmt(bq, 3)}</span><span style="position: relative; color: {t["up"]};">{fmt(bp, 1)}</span></div>'
            f'<div style="flex-grow: 1; position: relative; display: flex; justify-content: space-between; padding-left: 8px;">'
            f'<div style="position: absolute; left: 0; top: 2px; bottom: 2px; width: {aq/4.5*100:.0f}%; background: {t["downbg"]}; border-radius: 3px;"></div>'
            f'<span style="position: relative; color: {t["down"]};">{fmt(ap, 1)}</span><span style="position: relative; color: {t["muted"]};">{fmt(aq, 3)}</span></div></div>')
    tape = []
    for i, (p, q, up) in enumerate([(67432.1, 0.084, True), (67431.9, 0.310, False), (67432.4, 0.012, True), (67432.4, 1.205, True)]):
        tape.append(f'<div class="mono" style="height: 24px; display: flex; flex-direction: row; justify-content: space-between; font-size: 12px;">'
                    f'<span style="color: {t["muted"]};">12:41:0{3-i}</span><span style="color: {t["up"] if up else t["down"]};">{fmt(p, 1)}</span><span>{fmt(q, 3)}</span></div>')
    sec = lambda title, right='': (f'<div style="height: 40px; display: flex; flex-direction: row; align-items: center; justify-content: space-between;">'
                                   f'<span style="font-size: 14px; font-weight: 600;">{title}</span><span class="mono" style="font-size: 11px; color: {t["muted"]};">{right}</span></div>')
    body = phone(t, [
        header(t,
               f'<div style="display: flex; flex-direction: row; align-items: center; gap: 4px; margin-left: -12px;">{iconbtn(t, "back")}'
               f'<div style="display: flex; flex-direction: column; gap: 1px;"><span style="font-size: 17px; font-weight: 600;">BTC<span style="color: {t["muted"]}; font-weight: 500;">/USDT</span></span>'
               f'<span style="font-size: 11px; color: {t["muted"]};">Bitcoin · Binance</span></div></div>',
               status(t) + iconbtn(t, 'star', t['muted'])),
        f'<div style="padding: 8px 20px 0 20px; display: flex; flex-direction: column; gap: 6px;">'
        f'<div style="display: flex; flex-direction: row; align-items: baseline; gap: 12px;">'
        f'<span class="mono" style="font-size: 34px; font-weight: 600; letter-spacing: -0.01em;">{fmt(67432.10)}</span>{chip(t, "+2,14\u202f%", "up")}</div>'
        f'<div class="mono" style="display: flex; flex-direction: row; gap: 14px; font-size: 12px; color: {t["muted"]};">'
        f'<span>Макс <span style="color: {t["text"]};">68 412,0</span></span><span>Мин <span style="color: {t["text"]};">66 890,5</span></span>'
        f'<span>Объём <span style="color: {t["text"]};">18,4K BTC</span></span></div></div>',
        f'<div style="display: flex; flex-direction: row; gap: 4px; padding: 14px 20px 10px 20px;">{"".join(pills)}</div>',
        f'<div style="padding: 0 20px; display: flex; flex-direction: column; gap: 6px;">{chart}{vol}{axis}</div>',
        f'<div style="padding: 10px 20px 0 20px; display: flex; flex-direction: column;">{sec("Стакан", "Спред 0,6 · 0,001 %")}'
        f'<div class="mono" style="display: flex; flex-direction: row; justify-content: space-between; font-size: 10px; color: {t["muted"]}; text-transform: uppercase; letter-spacing: 0.06em; padding-bottom: 4px;">'
        f'<span>Объём</span><span>Покупка</span><span>Продажа</span><span>Объём</span></div>{"".join(book_rows)}</div>',
        f'<div style="padding: 8px 20px 0 20px; display: flex; flex-direction: column;">{sec("Сделки", "последние 30")}{"".join(tape)}</div>',
    ])
    return html_doc(t, body, 'Pair')

def portfolio(t):
    positions = [('BTC', 0.15, 64200.00, 10114.82, 6.3, True), ('ETH', 1.2, 3610.00, 4222.10, -2.5, False),
                 ('SOL', 40, 148.20, 6914.00, 16.6, True), ('TON', 250, 7.40, 1802.00, -2.6, False)]
    rows = []
    for sym, qty, avg, val, pnl, up in positions:
        rows.append(f'<div style="height: 72px; display: flex; flex-direction: row; align-items: center; justify-content: space-between; padding: 0 20px; border-bottom: 1px solid {t["line"]};">'
                    f'<div style="display: flex; flex-direction: column; gap: 4px;"><span style="font-size: 16px; font-weight: 600;">{sym}<span style="color: {t["muted"]}; font-weight: 500; font-size: 13px;">/USDT</span></span>'
                    f'<span class="mono" style="font-size: 12px; color: {t["muted"]};">{fmt(qty, 4 if qty < 1 else (2 if qty % 1 else 0))} × {fmt(avg)}</span></div>'
                    f'<div style="display: flex; flex-direction: column; align-items: flex-end; gap: 4px;"><span class="mono" style="font-size: 15px; font-weight: 500;">{fmt(val)}</span>'
                    f'{chip(t, ("+" if up else "−") + fmt(abs(pnl)) + "\u202f%", "up" if up else "down")}</div></div>')
    body = phone(t, [
        header(t, f'<span style="font-size: 24px; font-weight: 600; letter-spacing: -0.02em;">Портфель</span>', status(t) + '<div style="width: 12px;"></div>'),
        f'<div style="padding: 12px 20px 20px 20px; display: flex; flex-direction: column; gap: 8px;">'
        f'<span style="font-size: 12px; font-weight: 500; color: {t["muted"]}; letter-spacing: 0.02em;">Всего в USDT</span>'
        f'<div style="display: flex; flex-direction: row; align-items: baseline; gap: 12px;"><span class="mono" style="font-size: 34px; font-weight: 600; letter-spacing: -0.01em;">{fmt(23052.92)}</span>{chip(t, "+1\u202f204,10 · +5,5\u202f%", "up")}</div>'
        f'<div style="display: flex; flex-direction: row; gap: 16px; font-size: 12px; color: {t["muted"]};"><span>4 позиции</span><span>Котировки обновлены 12:41:03</span></div></div>',
        f'<div style="border-top: 1px solid {t["line"]}; display: flex; flex-direction: column;">{"".join(rows)}</div>',
        f'<div style="padding: 20px;"><div style="height: 52px; border-radius: 14px; background: {t["accent"]}; color: {t["onaccent"]}; display: flex; flex-direction: row; align-items: center; justify-content: center; gap: 8px; font-size: 15px; font-weight: 600;">{icon("plus", t["onaccent"], 20)}Добавить позицию</div></div>',
        tabbar(t, 'portfolio'),
    ])
    return html_doc(t, body, 'Portfolio')

def settings(t, theme_label='Стандартная · как в системе'):
    items = [('theme', 'Оформление', theme_label), ('source', 'Источник данных', 'Автоматически · Binance'), ('language', 'Язык', 'Русский'), ('about', 'О приложении', 'Источники, политика, версия')]
    rows = []
    for ic, title, val in items:
        rows.append(f'<div style="height: 64px; display: flex; flex-direction: row; align-items: center; gap: 14px; padding: 0 20px; border-bottom: 1px solid {t["line"]};">'
                    f'<div style="width: 40px; height: 40px; border-radius: 12px; background: {t["raised"]}; display: flex; align-items: center; justify-content: center;">{icon(ic, t["accent"], 22)}</div>'
                    f'<div style="flex-grow: 1; display: flex; flex-direction: column; gap: 3px;"><span style="font-size: 16px; font-weight: 500;">{title}</span><span style="font-size: 12px; color: {t["muted"]};">{val}</span></div>'
                    f'{icon("chevron", t["muted"], 20)}</div>')
    body = phone(t, [
        header(t, f'<span style="font-size: 24px; font-weight: 600; letter-spacing: -0.02em;">Настройки</span>', ''),
        f'<div style="margin-top: 8px; border-top: 1px solid {t["line"]}; display: flex; flex-direction: column;">{"".join(rows)}</div>',
        f'<div style="padding: 20px; font-size: 12px; color: {t["muted"]}; line-height: 1.5;">Котировки приходят напрямую с биржи. Портфель и настройки хранятся только на этом устройстве.</div>',
        tabbar(t, 'settings'),
    ])
    return html_doc(t, body, 'Settings')

def mini(t, w=96, h=64):
    """Tiny screen preview for the theme picker."""
    row = lambda up: (f'<div style="display: flex; flex-direction: row; align-items: center; justify-content: space-between; height: 12px;">'
                      f'<div style="width: 22px; height: 5px; border-radius: 3px; background: {t["text"]}; opacity: 0.8;"></div>'
                      f'<div style="width: 18px; height: 5px; border-radius: 3px; background: {t["up"] if up else t["down"]};"></div></div>')
    return (f'<div style="width: {w}px; height: {h}px; border-radius: 10px; background: {t["bg"]}; border: 1px solid {t["line"]}; padding: 8px 10px; box-sizing: border-box; display: flex; flex-direction: column; gap: 3px; overflow: hidden;">'
            f'<div style="display: flex; flex-direction: row; align-items: center; gap: 4px; height: 10px;">{ring(9, t["accent"], inner=False, gap=False)}<div style="width: 26px; height: 5px; border-radius: 3px; background: {t["text"]};"></div></div>'
            f'{row(True)}{row(False)}{row(True)}</div>')

def appearance(t, chosen='system'):
    opts = [('system', 'Как в системе', 'Стандартная: тёмная или светлая вслед за телефоном', [DARK, LIGHT]),
            ('dark', 'Тёмная', 'Стандартная, всегда тёмная', [DARK]),
            ('light', 'Светлая', 'Стандартная, всегда светлая', [LIGHT]),
            ('neon', 'Неоновая', 'Тёмная, циан и малина. Для тех, кто смотрит ночью', [NEON])]
    rows = []
    for key, title, sub, pals in opts:
        on = key == chosen
        mark = (f'<div style="flex-shrink: 0; width: 24px; height: 24px; border-radius: 12px; background: {t["accent"]}; display: flex; align-items: center; justify-content: center;">{icon("check", t["onaccent"], 16)}</div>'
                if on else f'<div style="flex-shrink: 0; width: 24px; height: 24px; border-radius: 12px; border: 1.5px solid {t["line"]};"></div>')
        rows.append(f'<div style="min-height: 88px; display: flex; flex-direction: row; align-items: center; gap: 14px; padding: 12px 20px; border-bottom: 1px solid {t["line"]}; box-sizing: border-box;">'
                    f'<div style="display: flex; flex-direction: row; gap: 4px;">{"".join(mini(p, 96 if len(pals) == 1 else 46) for p in pals)}</div>'
                    f'<div style="flex-grow: 1; display: flex; flex-direction: column; gap: 3px;"><span style="font-size: 16px; font-weight: 500;">{title}</span><span style="font-size: 12px; color: {t["muted"]}; line-height: 1.35;">{sub}</span></div>{mark}</div>')
    body = phone(t, [
        header(t, f'<div style="display: flex; flex-direction: row; align-items: center; gap: 4px; margin-left: -12px;">{iconbtn(t, "back")}<span style="font-size: 20px; font-weight: 600;">Оформление</span></div>', ''),
        f'<div style="margin-top: 8px; border-top: 1px solid {t["line"]}; display: flex; flex-direction: column;">{"".join(rows)}</div>',
    ])
    return html_doc(t, body, 'Appearance')

def about(t):
    li = lambda title, sub, ic='link': (f'<div style="min-height: 64px; display: flex; flex-direction: row; align-items: center; gap: 14px; padding: 10px 20px; border-bottom: 1px solid {t["line"]}; box-sizing: border-box;">'
                                       f'<div style="flex-grow: 1; display: flex; flex-direction: column; gap: 3px;"><span style="font-size: 15px; font-weight: 500;">{title}</span><span style="font-size: 12px; color: {t["muted"]}; line-height: 1.35;">{sub}</span></div>{icon(ic, t["muted"], 18)}</div>')
    body = phone(t, [
        header(t, f'<div style="display: flex; flex-direction: row; align-items: center; gap: 4px; margin-left: -12px;">{iconbtn(t, "back")}<span style="font-size: 20px; font-weight: 600;">О приложении</span></div>', ''),
        f'<div style="padding: 8px 20px 6px 20px; font-size: 12px; font-weight: 500; color: {t["muted"]}; letter-spacing: 0.02em;">Источники данных · условия проверены 05.09.2026</div>',
        li('Binance', 'Котировки, свечи, стакан и сделки. Условия API'),
        li('CoinGecko', 'Запасной источник цен. Условия API'),
        f'<div style="padding: 20px 20px 6px 20px; font-size: 12px; font-weight: 500; color: {t["muted"]}; letter-spacing: 0.02em;">Данные</div>',
        li('Что покидает устройство', 'Только запросы котировок к выбранному источнику. Портфель и настройки остаются на телефоне', 'about'),
        li('Политика конфиденциальности', 'denistc.github.io/trade_lens/privacy-policy'),
        li('Условия использования', 'denistc.github.io/trade_lens/terms-of-use'),
        f'<div style="margin-top: auto; padding: 0 20px 44px 20px; display: flex; flex-direction: column; align-items: center; gap: 10px;">{ring(28, t["accent"])}'
        f'<span style="font-size: 14px; font-weight: 600;">TradeLens</span>'
        f'<span class="mono" style="font-size: 12px; color: {t["muted"]};">0.1.0 (5) · App Store</span>'
        f'<span class="mono" style="font-size: 11px; color: {t["muted"]};">github.com/DenisTc/trade_lens</span></div>',
    ])
    return html_doc(t, body, 'About')

def app_icon(size, bg='#0C1117'):
    r = size * 0.225; c = size / 2; rr = size * 0.33; sw = size * 0.075
    circ = 2 * math.pi * rr
    bw = size * 0.11; bh = size * 0.26; wick = size * 0.12
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" fill="none">'
            f'<rect width="{size}" height="{size}" rx="{r:.1f}" fill="{bg}"></rect>'
            f'<circle cx="{c}" cy="{c}" r="{rr:.1f}" stroke="#F2B94A" stroke-width="{sw:.1f}" stroke-linecap="round" '
            f'stroke-dasharray="{circ*0.84:.1f} {circ*0.16:.1f}" transform="rotate(-55 {c} {c})"></circle>'
            f'<line x1="{c}" y1="{c-bh/2-wick:.1f}" x2="{c}" y2="{c+bh/2+wick:.1f}" stroke="#3DDC97" stroke-width="{max(1, size*0.035):.1f}" stroke-linecap="round"></line>'
            f'<rect x="{c-bw/2:.1f}" y="{c-bh/2:.1f}" width="{bw:.1f}" height="{bh:.1f}" rx="{bw*0.2:.1f}" fill="#3DDC97"></rect></svg>')

def icon_board(t):
    cell = lambda s, label: (f'<div style="display: flex; flex-direction: column; align-items: center; gap: 12px;">{app_icon(s)}'
                             f'<span class="mono" style="font-size: 11px; color: {t["muted"]};">{label}</span></div>')
    body = (f'<div style="width: 900px; height: 420px; background: {t["bg"]}; box-sizing: border-box; padding: 40px; display: flex; flex-direction: column; gap: 28px;">'
            f'<div style="display: flex; flex-direction: column; gap: 6px;"><span style="font-size: 22px; font-weight: 600;">Иконка приложения</span>'
            f'<span style="font-size: 13px; color: {t["muted"]};">Кольцо объектива с апертурным разрывом и одна свеча. Без градиентов, читается на 29 px. Тот же знак живёт в шапке и в индикаторе соединения.</span></div>'
            f'<div style="display: flex; flex-direction: row; align-items: flex-end; gap: 40px;">{cell(216, "1024 · App Store")}{cell(120, "120 · iPhone")}{cell(60, "60")}{cell(29, "29 · Settings")}'
            f'<div style="display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 20px; background: #F6F4EF; border-radius: 16px;">{app_icon(120)}<span class="mono" style="font-size: 11px; color: #5E6B78;">на светлом</span></div></div></div>')
    return html_doc(t, body, 'Icon')

def tokens_board(t):
    sw = lambda name, hexv, txt=None: (f'<div style="display: flex; flex-direction: column; gap: 6px; width: 96px;"><div style="height: 56px; border-radius: 10px; background: {hexv}; border: 1px solid {t["line"]};"></div>'
                                       f'<span style="font-size: 12px; font-weight: 500;">{name}</span><span class="mono" style="font-size: 11px; color: {t["muted"]};">{hexv}</span></div>')
    dark_sw = ''.join(sw(k, v) for k, v in [('bg', DARK['bg']), ('surface', DARK['surface']), ('raised', DARK['raised']), ('line', DARK['line']), ('text', DARK['text']), ('muted', DARK['muted']), ('accent', DARK['accent']), ('up', DARK['up']), ('down', DARK['down'])])
    light_sw = ''.join(sw(k, v) for k, v in [('bg', LIGHT['bg']), ('surface', LIGHT['surface']), ('raised', LIGHT['raised']), ('line', LIGHT['line']), ('text', LIGHT['text']), ('muted', LIGHT['muted']), ('accent', LIGHT['accent']), ('up', LIGHT['up']), ('down', LIGHT['down'])])
    typ = [('Заголовок экрана', 'Onest 600 · 24', 'font-size: 24px; font-weight: 600; letter-spacing: -0.02em;', 'Портфель'),
           ('Цена крупно', 'IBM Plex Mono 600 · 34', f'font-family: {MONO}; font-size: 34px; font-weight: 600;', fmt(67432.10)),
           ('Тикер', 'Onest 600 · 16', 'font-size: 16px; font-weight: 600;', 'BTC/USDT'),
           ('Цена в строке', 'IBM Plex Mono 500 · 15', f'font-family: {MONO}; font-size: 15px; font-weight: 500;', fmt(3518.42)),
           ('Текст', 'Onest 400 · 14', 'font-size: 14px;', 'Котировки приходят напрямую с биржи.'),
           ('Подпись', 'Onest 400 · 12 · muted', f'font-size: 12px; color: {t["muted"]};', 'Обновлено 12:41:03'),
           ('Ось графика', 'IBM Plex Mono 400 · 10', f'font-family: {MONO}; font-size: 10px; color: {t["muted"]};', fmt(68412, 0) + ' · 09:00')]
    typ_html = ''.join(f'<div style="display: flex; flex-direction: row; align-items: baseline; gap: 16px; padding: 8px 0; border-bottom: 1px solid {t["line"]};">'
                       f'<div style="width: 150px; display: flex; flex-direction: column; gap: 2px;"><span style="font-size: 12px; font-weight: 500;">{a}</span><span class="mono" style="font-size: 10px; color: {t["muted"]};">{b}</span></div>'
                       f'<span style="{c}">{d}</span></div>' for a, b, c, d in typ)
    comps = (f'<div style="display: flex; flex-direction: row; align-items: center; gap: 12px; flex-wrap: wrap;">{chip(t, "+2,14\u202f%", "up")}{chip(t, "−3,42\u202f%", "down")}'
             f'{status(t)}{status(t, False)}'
             f'<div style="height: 32px; padding: 0 12px; display: flex; align-items: center; border-radius: 16px; border: 1.5px solid {t["accent"]}; background: {t["accbg"]}; color: {t["accent"]}; font-size: 13px; font-weight: 600;">1ч</div>'
             f'<div style="height: 32px; padding: 0 12px; display: flex; align-items: center; border-radius: 16px; color: {t["muted"]}; font-size: 13px; font-weight: 600;">4ч</div>'
             f'<div style="height: 44px; padding: 0 20px; border-radius: 14px; background: {t["accent"]}; color: {t["onaccent"]}; display: flex; align-items: center; gap: 8px; font-size: 14px; font-weight: 600;">{icon("plus", t["onaccent"], 18)}Добавить позицию</div>'
             f'{ring(26, t["accent"])}{sparkline(walk(11, 24, 100, 0.02), t["up"])}{sparkline(walk(13, 24, 100, 0.02), t["down"])}</div>')
    neon_sw = ''.join(sw(k, v) for k, v in [('bg', NEON['bg']), ('surface', NEON['surface']), ('raised', NEON['raised']), ('line', NEON['line']), ('text', NEON['text']), ('muted', NEON['muted']), ('accent', NEON['accent']), ('up', NEON['up']), ('down', NEON['down'])])
    body = (f'<div style="width: 620px; height: 1420px; background: {t["bg"]}; box-sizing: border-box; padding: 32px; display: flex; flex-direction: column; gap: 22px;">'
            f'<span style="font-size: 22px; font-weight: 600;">Токены «Оптика»</span>'
            f'<div style="display: flex; flex-direction: column; gap: 8px;"><span style="font-size: 12px; font-weight: 500; color: {t["muted"]};">Тёмная тема</span><div style="display: flex; flex-direction: row; gap: 10px; flex-wrap: wrap;">{dark_sw}</div></div>'
            f'<div style="display: flex; flex-direction: column; gap: 8px;"><span style="font-size: 12px; font-weight: 500; color: {t["muted"]};">Светлая тема · бело-синяя, без бежевого</span><div style="display: flex; flex-direction: row; gap: 10px; flex-wrap: wrap;">{light_sw}</div></div>'
            f'<div style="display: flex; flex-direction: column; gap: 8px;"><span style="font-size: 12px; font-weight: 500; color: {t["muted"]};">Неоновая тема</span><div style="display: flex; flex-direction: row; gap: 10px; flex-wrap: wrap;">{neon_sw}</div></div>'
            f'<div style="display: flex; flex-direction: column;">{typ_html}</div>'
            f'<div style="display: flex; flex-direction: column; gap: 8px;"><span style="font-size: 12px; font-weight: 500; color: {t["muted"]};">Компоненты · радиусы 6 / 12 / 14 / 16 · строки 64 · отступ 20</span>{comps}</div></div>')
    return html_doc(t, body, 'Tokens')

# ---------- low-fi alternative directions ----------
def direction_editorial():
    t = dict(bg='#FBFAF7', surface='#FFFFFF', raised='#EFEDE7', line='#1A1A1A', text='#1A1A1A', muted='#6B6B6B', accent='#B4291E', up='#1A1A1A', down='#B4291E', onaccent='#fff', upbg='transparent', downbg='transparent', accbg='transparent')
    serif = "'Iowan Old Style', 'Palatino', Georgia, serif"
    rows = []
    for sym, name, price, chg, seed in PAIRS[:9]:
        col = t['down'] if chg < 0 else t['text']
        rows.append(f'<div style="height: 60px; display: flex; flex-direction: row; align-items: baseline; justify-content: space-between; border-bottom: 1px solid #D9D6CE; padding: 0 20px;">'
                    f'<div style="display: flex; flex-direction: column;"><span style="font-family: {serif}; font-size: 20px;">{name}</span><span class="mono" style="font-size: 11px; color: {t["muted"]}; letter-spacing: 0.08em;">{sym}/USDT</span></div>'
                    f'<div style="display: flex; flex-direction: row; gap: 18px; align-items: baseline;"><span class="mono" style="font-size: 15px;">{fmt(price, 2 if price >= 10 else 4)}</span>'
                    f'<span class="mono" style="font-size: 13px; color: {col}; width: 62px; text-align: right;">{"+" if chg >= 0 else "−"}{fmt(abs(chg))}</span></div></div>')
    body = phone(t, [
        f'<div style="padding: 20px 20px 8px 20px; display: flex; flex-direction: column; gap: 6px; border-bottom: 2px solid {t["text"]};">'
        f'<span class="mono" style="font-size: 11px; letter-spacing: 0.12em; color: {t["muted"]};">ВТОРНИК, 9 СЕНТЯБРЯ · 12:41</span>'
        f'<span style="font-family: {serif}; font-size: 44px; line-height: 1; letter-spacing: -0.02em;">Рынки</span></div>',
        f'<div style="display: flex; flex-direction: column;">{"".join(rows)}</div>',
        f'<div style="margin-top: auto; height: 84px; border-top: 1px solid {t["text"]}; display: flex; flex-direction: row; justify-content: space-around; align-items: flex-start; padding-top: 16px; box-sizing: border-box; font-family: {serif}; font-size: 15px;">'
        f'<span style="border-bottom: 2px solid {t["text"]};">Рынки</span><span style="color: {t["muted"]};">Портфель</span><span style="color: {t["muted"]};">Настройки</span></div>',
    ])
    return html_doc(t, body, 'Direction Editorial')

def direction_neon():
    t = dict(bg='#050507', surface='#0E0E14', raised='#16161F', line='#23232E', text='#F2F2FF', muted='#7A7A90', accent='#00E5FF', up='#00E5FF', down='#FF2E88', onaccent='#000', upbg='rgba(0,229,255,0.12)', downbg='rgba(255,46,136,0.12)', accbg='rgba(0,229,255,0.12)')
    cards = []
    for sym, name, price, chg, seed in PAIRS[:8]:
        col = t['up'] if chg >= 0 else t['down']
        cards.append(f'<div style="height: 132px; border-radius: 16px; background: {t["surface"]}; border: 1px solid {t["line"]}; padding: 14px; box-sizing: border-box; display: flex; flex-direction: column; justify-content: space-between; box-shadow: 0 0 24px {col}22;">'
                     f'<div style="display: flex; flex-direction: row; justify-content: space-between;"><span style="font-size: 15px; font-weight: 700;">{sym}</span><span class="mono" style="font-size: 12px; color: {col};">{"+" if chg >= 0 else "−"}{fmt(abs(chg))}%</span></div>'
                     f'{sparkline(walk(seed, 24, 100, 0.02), col, 138, 34, 0.25)}<span class="mono" style="font-size: 14px;">{fmt(price, 2 if price >= 10 else 4)}</span></div>')
    body = phone(t, [
        f'<div style="padding: 8px 20px 12px 20px; display: flex; flex-direction: row; justify-content: space-between; align-items: center;"><span style="font-size: 22px; font-weight: 800; letter-spacing: 0.08em; text-transform: uppercase; color: {t["accent"]}; text-shadow: 0 0 16px {t["accent"]};">TRADELENS</span>{icon("search", t["text"])}</div>',
        f'<div style="padding: 0 20px; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px;">{"".join(cards)}</div>',
        tabbar(t, 'markets'),
    ])
    return html_doc(t, body, 'Direction Neon')

files = {
    'Main.dc.html': markets(DARK), 'Pair.dc.html': pair(DARK), 'Portfolio.dc.html': portfolio(DARK),
    'Settings.dc.html': settings(DARK), 'Appearance.dc.html': appearance(DARK), 'About.dc.html': about(DARK),
    'MarketsLight.dc.html': markets(LIGHT, True), 'PairLight.dc.html': pair(LIGHT), 'PortfolioLight.dc.html': portfolio(LIGHT),
    'MarketsNeon.dc.html': markets(NEON), 'PairNeon.dc.html': pair(NEON), 'PortfolioNeon.dc.html': portfolio(NEON),
    'Icon.dc.html': icon_board(DARK), 'Tokens.dc.html': tokens_board(DARK),
}
for k, v in files.items(): (OUT / k).write_text(v)
for stale in ['DirectionEditorial.dc.html', 'DirectionNeon.dc.html']:
    (OUT / stale).unlink(missing_ok=True)

def ab(f, title, x, y, w=390, h=844): return {"file": f, "title": title, "x": x, "y": y, "w": w, "h": h}
canvas = {
  "artboards": [
    ab("Main.dc.html", "Рынки · стандартная тёмная", 0, 0), ab("Pair.dc.html", "Пара", 480, 0), ab("Portfolio.dc.html", "Портфель", 960, 0),
    ab("Settings.dc.html", "Настройки", 1440, 0), ab("Appearance.dc.html", "Оформление", 1920, 0), ab("About.dc.html", "О приложении", 2400, 0),
    ab("MarketsLight.dc.html", "Рынки · стандартная светлая", 0, 1000), ab("PairLight.dc.html", "Пара · светлая", 480, 1000), ab("PortfolioLight.dc.html", "Портфель · светлая", 960, 1000),
    ab("MarketsNeon.dc.html", "Рынки · неоновая", 1440, 1000), ab("PairNeon.dc.html", "Пара · неоновая", 1920, 1000), ab("PortfolioNeon.dc.html", "Портфель · неоновая", 2400, 1000),
    ab("Icon.dc.html", "Иконка", 0, 2000, 900, 420), ab("Tokens.dc.html", "Токены", 980, 2000, 620, 1420),
  ],
  "annotations": [
    {"id": "brief", "x": 0, "y": -240, "w": 620, "text": "Направление «Оптика», вторая итерация.\nНижнее меню — плавающее стекло: размытие фона, тонкая грань, подсветка активной вкладки; список уходит под него.\nТри темы: Стандартная (тёмная/светлая, вслед за системой или вручную) и Неоновая (только тёмная). Выбор — Настройки → Оформление.\nВерсия только на экране «О приложении», по центру внизу."},
    {"id": "light", "x": 0, "y": 950, "w": 420, "text": "Светлая: холодная бело-синяя база (#F2F5FA / #E5EBF5), жёлтый акцент темнее, чтобы держал контраст на белом. Бежевого нет."},
    {"id": "neon", "x": 1440, "y": 950, "w": 420, "text": "Неоновая: циан как акцент, неоновая зелень для роста, малина для падения. Стекло меню подсвечено цианом."},
    {"id": "icon-note", "x": 0, "y": 2470, "w": 320, "text": "Иконка без изменений. Токены — три палитры для tokens.dart."}
  ],
  "launch": {"view": "canvas"}
}
(OUT / 'canvas.json').write_text(json.dumps(canvas, ensure_ascii=False, indent=2))
print('wrote', len(files), 'artboards to', OUT)
