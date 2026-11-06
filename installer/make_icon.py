"""Draws the RestoreNest logo (same geometry as docs/img/logo.svg) and writes src/SystemCare/app.ico.
usage: python installer/make_icon.py   (needs Pillow)"""
import math
from pathlib import Path
from PIL import Image, ImageDraw

S = 4                      # supersampling; the logo is designed on a 256 grid
N = 256 * S


def p(x, y):
    return (x * S, y * S)


def quad(p0, p1, p2, steps=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / steps for i in range(steps + 1))]


def thick_line(d, pts, width, fill):
    d.line([p(*q) for q in pts], fill=fill, width=int(width * S), joint='curve')
    r = width * S / 2
    for q in (pts[0], pts[-1]):
        x, y = p(*q)
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


# background: diagonal gradient #4F86FF -> #1F4FD8 in a rounded square
bg = Image.new('RGB', (N, N))
px = bg.load()
c0, c1 = (0x4F, 0x86, 0xFF), (0x1F, 0x4F, 0xD8)
for y in range(N):
    for x in range(N):
        t = (x + y) / (2 * (N - 1))
        px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
mask = Image.new('L', (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, N - 1, N - 1], radius=58 * S, fill=255)
img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
img.paste(bg, (0, 0), mask)
d = ImageDraw.Draw(img)
white = (255, 255, 255, 255)

# restore arrow: clockwise loop around (128,128), r=74, from -50 deg to 230 deg (screen coordinates)
arc = [(128 + 74 * math.cos(math.radians(a)), 128 + 74 * math.sin(math.radians(a))) for a in [-50 + i * 280 / 120 for i in range(121)]]
thick_line(d, arc, 16, white)
head = [(103, 52), (85, 86), (62, 66)]
d.polygon([p(*q) for q in head], fill=white)
thick_line(d, head + [head[0]], 6, white)

# egg and nest
d.ellipse([p(128 - 19, 112 - 25), p(128 + 19, 112 + 25)], fill=(0xCF, 0xE0, 0xFF, 255))
nest = quad((78, 124), (128, 214), (178, 124)) + quad((178, 124), (128, 144), (78, 124))
d.polygon([p(*q) for q in nest], fill=white)
thick_line(d, nest + [nest[0]], 8, white)
blue = (0x2A, 0x5B, 0xE8, 255)
thick_line(d, quad((92, 142), (128, 160), (164, 142)), 5, blue)
thick_line(d, quad((104, 158), (128, 172), (152, 158)), 5, blue)

out = Path(__file__).resolve().parent.parent / 'src' / 'SystemCare' / 'app.ico'
base = img.resize((256, 256), Image.LANCZOS)
base.save(out, format='ICO', sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
img.resize((256, 256), Image.LANCZOS).save(Path(__file__).resolve().parent / 'icon-preview.png')
print('wrote', out)
