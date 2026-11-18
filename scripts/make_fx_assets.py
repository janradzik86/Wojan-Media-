"""Generates WoJan Media Studio's original effect textures (particles, frames,
impact sprites). All artwork is procedurally drawn here – no third-party assets.
Particle textures are 1080x1920 RGBA and tile seamlessly vertically and
horizontally (sprites crossing an edge are drawn on both sides)."""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
W, H = 1080, 1920
os.makedirs(OUT, exist_ok=True)

def heart(d, cx, cy, s, col):
    pts = []
    for i in range(60):
        t = i / 60 * 2 * math.pi
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * s / 17, cy - y * s / 17))
    d.polygon(pts, fill=col)

def star(d, cx, cy, r, col, n=5, inner=0.45, rot=0):
    pts = []
    for i in range(n * 2):
        a = rot - math.pi / 2 + i * math.pi / n
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=col)

def sparkle(d, cx, cy, r, col):
    star(d, cx, cy, r, col, n=4, inner=0.18)

def petal(d, cx, cy, r, col, rot):
    pts = []
    for i in range(40):
        t = i / 40 * 2 * math.pi
        x = r * 0.55 * math.sin(t)
        y = r * math.cos(t) * (0.9 + 0.1 * math.cos(t))
        if y < 0: x *= 0.6 + 0.4 * (1 + y / r)
        xr = x * math.cos(rot) - y * math.sin(rot)
        yr = x * math.sin(rot) + y * math.cos(rot)
        pts.append((cx + xr, cy + yr))
    d.polygon(pts, fill=col)

def leaf(d, cx, cy, r, col, rot):
    pts = []
    for i in range(50):
        t = i / 50 * 2 * math.pi
        x = r * 0.45 * math.sin(t) * (1 + 0.25 * math.sin(5 * t))
        y = r * math.cos(t)
        xr = x * math.cos(rot) - y * math.sin(rot); yr = x * math.sin(rot) + y * math.cos(rot)
        pts.append((cx + xr, cy + yr))
    d.polygon(pts, fill=col)
    d.line([(cx - r * math.sin(rot) * 0.9, cy + r * math.cos(rot) * 0.9), (cx + r * math.sin(rot), cy - r * math.cos(rot))], fill=(90, 50, 20, 200), width=max(1, int(r / 12)))

def snowflake(d, cx, cy, r, col):
    for k in range(6):
        a = k * math.pi / 3
        x2, y2 = cx + math.cos(a) * r, cy + math.sin(a) * r
        d.line([(cx, cy), (x2, y2)], fill=col, width=max(2, int(r / 7)))
        for f in (0.5, 0.75):
            bx, by = cx + math.cos(a) * r * f, cy + math.sin(a) * r * f
            for s in (-1, 1):
                b = a + s * math.pi / 4
                d.line([(bx, by), (bx + math.cos(b) * r * 0.3, by + math.sin(b) * r * 0.3)], fill=col, width=max(1, int(r / 10)))

def note(d, cx, cy, r, col):
    d.ellipse([cx - r * 0.5, cy + r * 0.2, cx + r * 0.3, cy + r * 0.8], fill=col)
    d.rectangle([cx + r * 0.18, cy - r * 0.8, cx + r * 0.32, cy + r * 0.5], fill=col)
    d.polygon([(cx + r * 0.32, cy - r * 0.8), (cx + r * 0.8, cy - r * 0.5), (cx + r * 0.8, cy - r * 0.25), (cx + r * 0.32, cy - r * 0.5)], fill=col)

def butterfly(d, cx, cy, r, col, rot):
    for s in (-1, 1):
        d.ellipse([cx + s * r * 0.05 - (r if s < 0 else 0), cy - r * 0.9, cx + s * r * 0.05 + (r if s > 0 else 0), cy + r * 0.1], fill=col)
        d.ellipse([cx + s * r * 0.05 - (r * 0.7 if s < 0 else 0), cy - r * 0.05, cx + s * r * 0.05 + (r * 0.7 if s > 0 else 0), cy + r * 0.75], fill=col)
    d.rectangle([cx - r * 0.06, cy - r * 0.8, cx + r * 0.06, cy + r * 0.7], fill=(40, 30, 30, 255))

def flower(d, cx, cy, r, col, center=(255, 200, 40, 255)):
    for k in range(5):
        a = k * 2 * math.pi / 5
        d.ellipse([cx + math.cos(a) * r * 0.55 - r * 0.42, cy + math.sin(a) * r * 0.55 - r * 0.42, cx + math.cos(a) * r * 0.55 + r * 0.42, cy + math.sin(a) * r * 0.55 + r * 0.42], fill=col)
    d.ellipse([cx - r * 0.3, cy - r * 0.3, cx + r * 0.3, cy + r * 0.3], fill=center)

def bill(d, cx, cy, r, col, rot):
    w, h = r * 2, r
    pts = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    pts = [(cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)) for x, y in pts]
    d.polygon(pts, fill=col)
    d.ellipse([cx - h * 0.28, cy - h * 0.28, cx + h * 0.28, cy + h * 0.28], fill=(30, 110, 50, 255))

def balloon(d, cx, cy, r, col):
    d.ellipse([cx - r * 0.75, cy - r, cx + r * 0.75, cy + r * 0.8], fill=col)
    d.line([(cx, cy + r * 0.8), (cx + r * 0.1, cy + r * 2.2)], fill=(240, 240, 240, 200), width=2)

def diamond(d, cx, cy, r, col):
    d.polygon([(cx, cy - r), (cx + r * 0.7, cy - r * 0.2), (cx, cy + r), (cx - r * 0.7, cy - r * 0.2)], fill=col)
    d.line([(cx - r * 0.7, cy - r * 0.2), (cx + r * 0.7, cy - r * 0.2)], fill=(255, 255, 255, 180), width=2)

def tile(name, count, draw_fn, sizes, glow=0, seed=1, blur=0):
    rnd = random.Random(seed)
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for _ in range(count):
        layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        s = rnd.uniform(*sizes)
        for dx in (-W, 0, W):
            for dy in (-H, 0, H):
                if -s * 3 < x + dx < W + s * 3 and -s * 3 < y + dy < H + s * 3:
                    draw_fn(d, x + dx, y + dy, s, rnd)
        im = Image.alpha_composite(im, layer)
    if blur: im = im.filter(ImageFilter.GaussianBlur(blur))
    if glow:
        g = im.filter(ImageFilter.GaussianBlur(glow))
        im = Image.alpha_composite(g, im)
    im.save(os.path.join(OUT, f'p_{name}.png'), optimize=True)

R = lambda rnd, cols: rnd.choice(cols)
tile('hearts_red', 34, lambda d, x, y, s, r: heart(d, x, y, s, R(r, [(230, 20, 60, 235), (255, 60, 90, 235), (200, 0, 40, 235)])), (18, 46), glow=6)
tile('hearts_pink', 40, lambda d, x, y, s, r: heart(d, x, y, s, R(r, [(255, 120, 180, 230), (255, 170, 210, 230), (255, 80, 160, 230)])), (14, 40), glow=8, seed=2)
tile('stars_gold', 42, lambda d, x, y, s, r: star(d, x, y, s, R(r, [(255, 210, 60, 240), (255, 230, 120, 240), (240, 180, 30, 240)]), rot=r.uniform(0, 1)), (10, 30), glow=8, seed=3)
tile('sparkles', 70, lambda d, x, y, s, r: sparkle(d, x, y, s, (255, 255, 255, 240)), (6, 22), glow=6, seed=4)
tile('confetti', 160, lambda d, x, y, s, r: d.polygon([(x + math.cos(a) * s, y + math.sin(a) * s) for a in [r.uniform(0, 6.28) + k * 1.9 for k in range(3)]] if r.random() < .4 else [(x - s, y - s * .35), (x + s, y - s * .35), (x + s, y + s * .35), (x - s, y + s * .35)], fill=R(r, [(255, 64, 64, 240), (255, 200, 0, 240), (60, 200, 255, 240), (120, 255, 120, 240), (255, 100, 220, 240), (255, 255, 255, 240)])), (6, 14), seed=5)
tile('petals', 46, lambda d, x, y, s, r: petal(d, x, y, s, R(r, [(255, 183, 197, 235), (255, 200, 215, 235), (250, 160, 185, 235)]), r.uniform(0, 6.28)), (10, 22), seed=6, glow=2)
tile('leaves', 34, lambda d, x, y, s, r: leaf(d, x, y, s, R(r, [(214, 108, 28, 240), (190, 60, 20, 240), (230, 170, 40, 240), (150, 90, 30, 240)]), r.uniform(0, 6.28)), (16, 34), seed=7)
tile('snowflakes', 40, lambda d, x, y, s, r: snowflake(d, x, y, s, (255, 255, 255, 235)), (10, 30), glow=4, seed=8)
tile('bubbles', 30, lambda d, x, y, s, r: (d.ellipse([x - s, y - s, x + s, y + s], outline=(220, 240, 255, 200), width=max(2, int(s / 8))), d.ellipse([x - s * .5, y - s * .6, x - s * .1, y - s * .25], fill=(255, 255, 255, 170))), (14, 46), seed=9, glow=3)
tile('notes', 30, lambda d, x, y, s, r: note(d, x, y, s, R(r, [(255, 255, 255, 230), (53, 208, 186, 230), (255, 79, 163, 230)])), (18, 40), glow=6, seed=10)
tile('butterflies', 18, lambda d, x, y, s, r: butterfly(d, x, y, s, R(r, [(120, 190, 255, 230), (255, 160, 60, 230), (220, 120, 255, 230), (255, 230, 90, 230)]), 0), (16, 30), seed=11, glow=3)
tile('flowers', 26, lambda d, x, y, s, r: flower(d, x, y, s, R(r, [(255, 220, 60, 235), (255, 255, 255, 235), (255, 140, 180, 235), (180, 120, 255, 235)])), (14, 30), seed=12)
tile('money', 26, lambda d, x, y, s, r: bill(d, x, y, s, (90, 190, 110, 240), r.uniform(0, 6.28)), (18, 34), seed=13)
tile('balloons', 18, lambda d, x, y, s, r: balloon(d, x, y, s, R(r, [(255, 60, 80, 235), (255, 200, 40, 235), (60, 160, 255, 235), (160, 90, 255, 235)])), (26, 48), seed=14, glow=2)
tile('diamonds', 40, lambda d, x, y, s, r: diamond(d, x, y, s, R(r, [(160, 230, 255, 235), (220, 250, 255, 235), (120, 200, 255, 235)])), (8, 22), seed=15, glow=8)
tile('gold_dust', 320, lambda d, x, y, s, r: d.ellipse([x - s, y - s, x + s, y + s], fill=(255, 215, 120, int(r.uniform(170, 255)))), (2.5, 6.5), seed=16, glow=5)
tile('fireflies', 60, lambda d, x, y, s, r: d.ellipse([x - s, y - s, x + s, y + s], fill=(220, 255, 120, 255)), (3, 7), seed=17, glow=10)
tile('embers', 120, lambda d, x, y, s, r: d.ellipse([x - s, y - s * 1.6, x + s, y + s * 1.6], fill=R(r, [(255, 140, 30, 255), (255, 90, 20, 255), (255, 200, 80, 255)])), (2, 5), seed=18, glow=6)
tile('bokeh', 26, lambda d, x, y, s, r: d.ellipse([x - s, y - s, x + s, y + s], fill=R(r, [(255, 220, 150, 90), (255, 180, 210, 90), (160, 220, 255, 90), (255, 255, 255, 80)])), (30, 90), seed=19, blur=6)
tile('stars_white', 150, lambda d, x, y, s, r: star(d, x, y, s, (255, 255, 255, int(r.uniform(190, 255))), n=4, inner=0.3), (6, 15), seed=20, glow=5)
tile('rain_drops', 240, lambda d, x, y, s, r: d.line([(x, y), (x - s * 0.15, y + s)], fill=(215, 230, 255, 210), width=5), (36, 80), seed=21)
tile('hearts_gold', 30, lambda d, x, y, s, r: heart(d, x, y, s, R(r, [(255, 205, 80, 240), (255, 225, 140, 240)])), (14, 36), glow=8, seed=22)

# ---- frames (9:16 base; renderer stretches for other aspects – borders only)
def frame(name, fn, size=(W, H)):
    im = Image.new('RGBA', size, (0, 0, 0, 0)); d = ImageDraw.Draw(im); fn(im, d, size[0], size[1])
    im.save(os.path.join(OUT, f'f_{name}.png'), optimize=True)

def film(im, d, w, h):
    d.rectangle([0, 0, 90, h], fill=(10, 10, 10, 255)); d.rectangle([w - 90, 0, w, h], fill=(10, 10, 10, 255))
    for y in range(20, h, 70):
        for x0 in (25, w - 65):
            d.rounded_rectangle([x0, y, x0 + 40, y + 40], radius=6, fill=(0, 0, 0, 0))
def polaroid(im, d, w, h):
    d.rectangle([0, 0, w, h], fill=(250, 250, 245, 255)); d.rectangle([60, 60, w - 60, h - 320], fill=(0, 0, 0, 0))
def neon(im, d, w, h):
    lay = Image.new('RGBA', (w, h), (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
    dl.rounded_rectangle([40, 40, w - 40, h - 40], radius=50, outline=(0, 240, 255, 255), width=14)
    dl.rounded_rectangle([80, 80, w - 80, h - 80], radius=40, outline=(255, 40, 200, 255), width=10)
    g = lay.filter(ImageFilter.GaussianBlur(16)); im.alpha_composite(g); im.alpha_composite(g); im.alpha_composite(lay)
def rounded(im, d, w, h):
    m = Image.new('L', (w, h), 255); dm = ImageDraw.Draw(m); dm.rounded_rectangle([30, 30, w - 30, h - 30], radius=90, fill=0)
    im.paste((8, 8, 10, 255), mask=m)
def gold(im, d, w, h):
    for i, c in enumerate([(120, 80, 20), (220, 170, 60), (255, 230, 140), (200, 150, 50), (120, 80, 20)]):
        d.rectangle([i * 12, i * 12, w - i * 12, h - i * 12], outline=c + (255,), width=12)
    for x, y in [(60, 60), (w - 60, 60), (60, h - 60), (w - 60, h - 60)]:
        star(d, x, y, 46, (255, 225, 130, 255), n=8, inner=0.5)
def hearts_border(im, d, w, h):
    for x in range(40, w, 90):
        heart(d, x, 45, 30, (255, 60, 110, 240)); heart(d, x, h - 45, 30, (255, 60, 110, 240))
    for y in range(130, h - 90, 90):
        heart(d, 45, y, 30, (255, 120, 170, 240)); heart(d, w - 45, y, 30, (255, 120, 170, 240))
def stars_border(im, d, w, h):
    rnd = random.Random(3)
    for _ in range(140):
        edge = rnd.random()
        x = rnd.uniform(0, w) if edge < .5 else rnd.choice([rnd.uniform(0, 110), rnd.uniform(w - 110, w)])
        y = rnd.choice([rnd.uniform(0, 110), rnd.uniform(h - 110, h)]) if edge < .5 else rnd.uniform(0, h)
        star(d, x, y, rnd.uniform(8, 24), (255, 230, 120, 230), rot=rnd.uniform(0, 1))
    im.alpha_composite(im.filter(ImageFilter.GaussianBlur(5)))
def viewfinder(im, d, w, h):
    c = (255, 255, 255, 235); L = 120; t = 8; m = 70
    for (x, y, sx, sy) in [(m, m, 1, 1), (w - m, m, -1, 1), (m, h - m, 1, -1), (w - m, h - m, -1, -1)]:
        d.rectangle([min(x, x + sx * L), y - t // 2 if sy > 0 else y - t // 2, max(x, x + sx * L), y + t // 2], fill=c)
        d.rectangle([x - t // 2, min(y, y + sy * L), x + t // 2, max(y, y + sy * L)], fill=c)
    d.ellipse([m + 30, m + 40, m + 70, m + 80], fill=(255, 30, 30, 255))
    try: f = ImageFont.truetype(sys.argv[2], 54)
    except Exception: f = None
    d.text((m + 90, m + 30), 'REC', fill=c, font=f)
    d.line([(w / 2 - 40, h / 2), (w / 2 + 40, h / 2)], fill=c, width=4); d.line([(w / 2, h / 2 - 40), (w / 2, h / 2 + 40)], fill=c, width=4)
def comic(im, d, w, h):
    d.rectangle([0, 0, w, h], outline=(0, 0, 0, 255), width=36); d.rectangle([36, 36, w - 36, h - 36], outline=(255, 255, 255, 255), width=10)
def torn(im, d, w, h):
    rnd = random.Random(5); pts = []
    m = Image.new('L', (w, h), 255); dm = ImageDraw.Draw(m)
    for x in range(0, w + 20, 20): pts.append((x, 60 + rnd.uniform(-25, 25)))
    for y in range(0, h + 20, 20): pts.append((w - 60 + rnd.uniform(-25, 25), y))
    for x in range(w, -20, -20): pts.append((x, h - 60 + rnd.uniform(-25, 25)))
    for y in range(h, -20, -20): pts.append((60 + rnd.uniform(-25, 25), y))
    dm.polygon(pts, fill=0); im.paste((245, 242, 232, 255), mask=m)
def vhs_ui(im, d, w, h):
    try: f = ImageFont.truetype(sys.argv[2], 60)
    except Exception: f = None
    d.text((70, 90), 'PLAY', fill=(255, 255, 255, 230), font=f); d.polygon([(200, 104), (200, 150), (240, 127)], fill=(255, 255, 255, 230)); d.text((70, h - 170), 'SP  0:00:00', fill=(255, 255, 255, 230), font=f)
    for y in range(0, h, 6): d.line([(0, y), (w, y)], fill=(0, 0, 0, 40))
def cinema(im, d, w, h):
    d.rectangle([0, 0, w, int(h * 0.12)], fill=(0, 0, 0, 255)); d.rectangle([0, int(h * 0.88), w, h], fill=(0, 0, 0, 255))
def grunge(im, d, w, h):
    rnd = random.Random(9); m = Image.new('L', (w, h), 0); dm = ImageDraw.Draw(m)
    for _ in range(9000):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        e = min(x, y, w - x, h - y)
        if rnd.random() < math.exp(-e / 60): dm.ellipse([x - 6, y - 6, x + 6, y + 6], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(3)); im.paste((15, 12, 10, 255), mask=m)
for n, fn in [('film', film), ('polaroid', polaroid), ('neon', neon), ('rounded', rounded), ('gold', gold), ('hearts', hearts_border), ('stars', stars_border), ('viewfinder', viewfinder), ('comic', comic), ('torn', torn), ('vhs', vhs_ui), ('cinema', cinema), ('grunge', grunge)]:
    frame(n, fn)

# ---- impact / light sprites (square, centred)
def sq(name, fn, s=1024):
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im); im = fn(im, d, s) or im
    im.save(os.path.join(OUT, f's_{name}.png'), optimize=True)
def ring(im, d, s):
    d.ellipse([s * .1, s * .1, s * .9, s * .9], outline=(255, 255, 255, 255), width=int(s * .035)); return im.filter(ImageFilter.GaussianBlur(4))
def burst(im, d, s):
    for r in range(int(s / 2), 0, -4):
        a = int(255 * (1 - r / (s / 2)) ** 2.2); d.ellipse([s / 2 - r, s / 2 - r, s / 2 + r, s / 2 + r], fill=(255, 250, 235, a))
def rays(im, d, s):
    c = s / 2
    for k in range(28):
        a = k * 2 * math.pi / 28; w = 0.05
        d.polygon([(c, c), (c + math.cos(a - w) * s, c + math.sin(a - w) * s), (c + math.cos(a + w) * s, c + math.sin(a + w) * s)], fill=(255, 245, 210, 70))
    return im.filter(ImageFilter.GaussianBlur(10))
def speed_lines(im, d, s):
    rnd = random.Random(4); c = s / 2
    for _ in range(140):
        a = rnd.uniform(0, 2 * math.pi); r0 = rnd.uniform(s * .28, s * .42); w = rnd.uniform(0.004, 0.012)
        d.polygon([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a - w) * s, c + math.sin(a - w) * s), (c + math.cos(a + w) * s, c + math.sin(a + w) * s)], fill=(255, 255, 255, 230))
def halftone(im, d, s):
    for y in range(0, s, 18):
        for x in range(0, s, 18):
            r = 2 + 5 * (math.hypot(x - s / 2, y - s / 2) / (s / 1.4)); d.ellipse([x - r, y - r, x + r, y + r], fill=(0, 0, 0, 110))
def aura(im, d, s):
    d.ellipse([s * .12, s * .12, s * .88, s * .88], outline=(120, 200, 255, 255), width=int(s * .06)); return im.filter(ImageFilter.GaussianBlur(30))
for n, fn in [('ring', ring), ('burst', burst), ('rays', rays), ('speed_lines', speed_lines), ('halftone', halftone), ('aura', aura)]:
    sq(n, fn)
print('fx assets ok', len(os.listdir(OUT)))
