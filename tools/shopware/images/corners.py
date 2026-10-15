"""Tile zooms around estimated points with a 0.5 % grid, for reading --patch and --quad corners.

usage: corners.py IN OUT "x,y x,y ..." [RADIUS [FACTOR]]

Points and RADIUS are fractions of the image width. Each point gets a window of
plus or minus RADIUS, enlarged FACTOR times, with labelled grid lines every
0.005 so a corner can be read to that precision.
"""
import sys
from PIL import Image, ImageDraw
src, out, pts = sys.argv[1], sys.argv[2], [tuple(map(float, p.split(","))) for p in sys.argv[3].split()]
im = Image.open(src).convert("RGB"); w, h = im.size
R, F, T = float(sys.argv[4]) if len(sys.argv) > 4 else 0.025, int(sys.argv[5]) if len(sys.argv) > 5 else 5, []
for cx, cy in pts:
    x0, y0 = cx - R, cy - R * w / h
    x1, y1 = cx + R, cy + R * w / h
    c = im.crop((round(x0 * w), round(y0 * h), round(x1 * w), round(y1 * h)))
    c = c.resize((c.width * F, c.height * F), Image.NEAREST); d = ImageDraw.Draw(c)
    k = round(x0 / 0.005)
    while k * 0.005 <= x1:
        px = (k * 0.005 - x0) * w * F; d.line((px, 0, px, c.height), fill=(0, 200, 255) if k % 2 == 0 else (0, 90, 140)); d.text((px + 2, 2 + 12 * (k % 2)), f"{k*0.005:.3f}", fill=(0, 255, 255)); k += 1
    k = round(y0 / 0.005)
    while k * 0.005 <= y1:
        py = (k * 0.005 - y0) * h * F; d.line((0, py, c.width, py), fill=(255, 60, 60) if k % 2 == 0 else (140, 30, 30)); d.text((2, py + 2), f"{k*0.005:.3f}", fill=(255, 255, 0)); k += 1
    T.append(c)
sheet = Image.new("RGB", (sum(t.width for t in T[:2]), T[0].height * ((len(T) + 1) // 2)))
for i, t in enumerate(T):
    sheet.paste(t, ((i % 2) * T[0].width, (i // 2) * T[0].height))
sheet.save(out)
