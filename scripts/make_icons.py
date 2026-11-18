"""Generates the WoJan Media Studio logo & platform icons (original artwork)."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
def logo(size):
    S = size * 4
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = S * 0.22
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=r, fill=(17, 19, 23, 255))
    # gradient ring
    cx = cy = S / 2
    for i in range(360):
        a0 = math.radians(i); t = i / 360
        col = tuple(int(c1 + (c2 - c1) * t) for c1, c2 in zip((53, 208, 186), (255, 79, 163))) + (255,)
        R = S * 0.36
        d.pieslice([cx - R, cy - R, cx + R, cy + R], i - 90, i - 89 + 1.5, fill=col)
    R2 = S * 0.29
    d.ellipse([cx - R2, cy - R2, cx + R2, cy + R2], fill=(17, 19, 23, 255))
    # "W" made of equalizer bars
    bars = [0.55, 0.85, 0.4, 0.85, 0.55]
    bw = S * 0.055; gap = S * 0.025
    total = len(bars) * bw + (len(bars) - 1) * gap
    x = cx - total / 2
    for h in bars:
        hh = S * 0.34 * h
        d.rounded_rectangle([x, cy + S * 0.15 - hh, x + bw, cy + S * 0.15], radius=bw / 2, fill=(242, 244, 247, 255))
        x += bw + gap
    # play triangle accent
    t = S * 0.07
    d.polygon([(cx + S * 0.2, cy - S * 0.2), (cx + S * 0.2, cy - S * 0.2 + t * 1.4), (cx + S * 0.2 + t * 1.2, cy - S * 0.2 + t * 0.7)], fill=(255, 79, 163, 255))
    return im.resize((size, size), Image.LANCZOS)

def save(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    logo(size).save(path)

app = os.path.join(ROOT, 'source/wojan_media_studio')
save(os.path.join(app, 'assets/branding/logo.png'), 512)
save(os.path.join(ROOT, 'assets/logo_1024.png'), 1024)
for name, sz in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(os.path.join(app, f'android/app/src/main/res/mipmap-{name}/ic_launcher.png'), sz)
ico = logo(256)
ico.save(os.path.join(app, 'windows/runner/resources/app_icon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('icons ok')
