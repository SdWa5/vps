"""Turn one product photo into shop variants: cutout, white, light and dark square.

Runs inside the image that shop-images.sh builds; see its help for the wrapper.

usage: shopimg.py IN OUTDIR NAME [--crop x0,y0,x1,y1] [--erase x0,y0,x1,y1]...
       [--keep x0,y0,x1,y1]... [--gain G] [--patch "x,y x,y ..."]... [--neutral]
       [--quad "x,y x,y x,y x,y"]

Boxes are fractions of the (cropped) image. --erase removes a region from the
foreground mask (for objects that must not appear), --keep forces a region into
it. --gain brightens the subject (1.0 = unchanged). --patch fills a polygon, in
fractions of the uncropped image, by smooth diffusion from the pixels around it;
its top edge reflects, so nothing above the polygon bleeds in. --neutral scales
the colour channels so the subject averages grey (for grey filament only).

--quad corrects perspective. It names the corners of a face that is a rectangle
in reality, as TL TR BR BL in fractions of the uncropped image, read off a grid
zoom (corners.py). The cutout is warped so that face becomes a rectangle with
the mean width and height of the measured quad.
"""
import argparse
import pathlib

import numpy as np

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

SIZE = 2000
FILL = 0.82
BACKGROUNDS = {
    "white": ((255, 255, 255), (255, 255, 255)),
    "light": ((252, 252, 253), (232, 232, 238)),
    "dark": ((34, 34, 48), (10, 10, 15)),
}


def box(spec, w, h):
    x0, y0, x1, y1 = (float(v) for v in spec.split(","))
    return int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)


def radial(size, inner, outer):
    """Vertical-radial studio gradient, lighter in the middle behind the subject."""
    grad = Image.radial_gradient("L").resize((size * 2, size * 2)).crop(
        (size // 2, size // 3, size // 2 + size, size // 3 + size))
    return Image.composite(Image.new("RGB", (size, size), outer), Image.new("RGB", (size, size), inner), grad)


def patch(img, spec):
    """Fill the polygon SPEC by Laplace diffusion, reflecting at its top edge."""
    w, h = img.size
    pts = [(float(x) * w, float(y) * h) for x, y in (p.split(",") for p in spec.split())]
    poly = Image.new("L", img.size, 0)
    ImageDraw.Draw(poly).polygon(pts, fill=255)
    x0, y0, x1, y1 = poly.getbbox()
    x0, x1, y1 = max(x0 - 1, 0), min(x1 + 1, w), min(y1 + 1, h)
    a = np.asarray(img, dtype=np.float64).copy()
    m = np.asarray(poly)[y0:y1, x0:x1] > 0
    r = a[y0:y1, x0:x1]
    known = r[~m]
    r[m] = known.mean(axis=0)
    for _ in range(1500):
        up = np.vstack([r[:1], r[:-1]])
        down = np.vstack([r[1:], r[-1:]])
        left = np.hstack([r[:, :1], r[:, :-1]])
        right = np.hstack([r[:, 1:], r[:, -1:]])
        r[m] = ((up + down + left + right) / 4)[m]
    noise = np.random.default_rng(0).normal(0, known.std(axis=0).mean() * 0.35, (int(m.sum()), 1))
    r[m] = r[m] + noise
    a[y0:y1, x0:x1] = r
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def homography(src, dst):
    """Coefficients mapping DST points onto SRC points, as PIL's PERSPECTIVE wants them."""
    rows, rhs = [], []
    for (x, y), (u, v) in zip(dst, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); rhs.append(u)
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y]); rhs.append(v)
    return np.linalg.solve(np.array(rows), np.array(rhs))


def upright(cut, spec, off, full):
    """Warp CUT so the quad SPEC (fractions of the uncropped image) becomes a rectangle."""
    (fw, fh), (ox, oy) = full, off
    q = np.array([(float(x) * fw - ox, float(y) * fh - oy) for x, y in (p.split(",") for p in spec.split())])
    width = (np.linalg.norm(q[1] - q[0]) + np.linalg.norm(q[2] - q[3])) / 2
    height = (np.linalg.norm(q[3] - q[0]) + np.linalg.norm(q[2] - q[1])) / 2
    cx, cy = q.mean(axis=0)
    rect = np.array([(cx - width / 2, cy - height / 2), (cx + width / 2, cy - height / 2),
                     (cx + width / 2, cy + height / 2), (cx - width / 2, cy + height / 2)])

    fwd = homography(rect, q)  # source pixel -> corrected pixel
    mapped = []
    for x, y in [(0, 0), (cut.width, 0), (cut.width, cut.height), (0, cut.height)]:
        d = fwd[6] * x + fwd[7] * y + 1
        mapped.append(((fwd[0] * x + fwd[1] * y + fwd[2]) / d, (fwd[3] * x + fwd[4] * y + fwd[5]) / d))
    m = np.array(mapped)
    shift = -m.min(axis=0)
    size = tuple(int(v) + 1 for v in m.max(axis=0) + shift)
    back = homography(q, rect + shift)  # corrected pixel -> source pixel, as PIL wants it
    return cut.transform(size, Image.PERSPECTIVE, tuple(back), Image.BICUBIC)


def neutral(img, mask):
    a = np.asarray(img, dtype=np.float64)
    sel = np.asarray(mask) > 128
    mean = a[sel].mean(axis=0)
    a = a * (mean.mean() / mean)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("outdir")
    ap.add_argument("name")
    ap.add_argument("--crop")
    ap.add_argument("--erase", action="append", default=[])
    ap.add_argument("--keep", action="append", default=[])
    ap.add_argument("--gain", type=float, default=1.0)
    ap.add_argument("--patch", action="append", default=[])
    ap.add_argument("--neutral", action="store_true")
    ap.add_argument("--quad")
    a = ap.parse_args()

    out = pathlib.Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    img = ImageOps.exif_transpose(Image.open(a.src)).convert("RGB")
    for spec in a.patch:
        img = patch(img, spec)
    full = img.size
    off = (0, 0)
    if a.crop:
        b = box(a.crop, *img.size)
        off = b[:2]
        img = img.crop(b)
    w, h = img.size

    from rembg import new_session, remove  # imported here so the geometry can be tested without it

    mask = remove(img, session=new_session("birefnet-general"), only_mask=True, post_process_mask=True)
    draw = ImageDraw.Draw(mask)
    for spec in a.erase:
        draw.rectangle(box(spec, w, h), fill=0)
    for spec in a.keep:
        draw.rectangle(box(spec, w, h), fill=255)

    subject = neutral(img, mask) if a.neutral else img
    subject = ImageOps.autocontrast(subject, cutoff=0.5, preserve_tone=True)
    if a.gain != 1.0:
        subject = ImageEnhance.Brightness(subject).enhance(a.gain)
    subject = subject.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=3))
    cut = subject.convert("RGBA")
    cut.putalpha(mask)
    if a.quad:
        cut = upright(cut, a.quad, off, full)
    cut = cut.crop(cut.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox())
    cut.save(out / f"{a.name}-cutout.png")

    scale = min(SIZE * FILL / cut.width, SIZE * FILL / cut.height)
    sub = cut.resize((round(cut.width * scale), round(cut.height * scale)), Image.LANCZOS)
    x = (SIZE - sub.width) // 2
    y = SIZE - round(SIZE * (1 - FILL) / 2) - sub.height

    for variant, (inner, outer) in BACKGROUNDS.items():
        canvas = radial(SIZE, inner, outer).convert("RGBA")
        shadow = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(shadow).ellipse(
            (x + sub.width * 0.04, y + sub.height - 34, x + sub.width * 0.96, y + sub.height + 10), fill=150)
        shadow = shadow.filter(ImageFilter.GaussianBlur(22))
        tone = (0, 0, 0)
        strength = 0.55 if variant != "dark" else 0.9
        canvas = Image.composite(Image.new("RGBA", canvas.size, tone + (255,)), canvas,
                                 shadow.point(lambda v: int(v * strength)))
        canvas.alpha_composite(sub, (x, y))
        canvas.convert("RGB").save(out / f"{a.name}-{variant}.jpg", quality=90, optimize=True, progressive=True)
    print(a.name, "ok", cut.size)


if __name__ == "__main__":
    main()
