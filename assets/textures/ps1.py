"""Turn AI texture images into small PS1-style tiles.
usage: ps1.py RAW_DIR OUT_DIR SHEET_PNG
- per axis: if the image repeats (window grid, slabs, roof rows) crop a whole number of
  repeats so it tiles with no seam; otherwise cross-fade the seam on that axis
- downscale, colour-tweak, quantize to a small palette (no dither = clean pixels)
"""
import sys, os
from PIL import Image, ImageDraw, ImageEnhance, ImageChops, ImageFilter

RAW, OUT, SHEET = sys.argv[1:4]
os.makedirs(OUT, exist_ok=True)

# name: (out_w, out_h, crop aspect w/h, colours, options)  reps = wanted repeats (x, y)
SPEC = {
    'facade_brick':  (128, 256, 7/9, 40, {'reps': (2, 3)}),
    'facade_office': (128, 256, 7/9, 32, {'reps': (3, 3)}),
    'facade_stucco': (128, 256, 7/9, 40, {'reps': (2, 3)}),
    'sidewalk':      (128, 128, 1.0, 24, {'reps': (3, 3), 'thr': .2}),
    'roof':          (128, 128, 1.0, 32, {'reps': (6, 6), 'thr': .2}),
    'shutter':       (128, 128, 1.0, 24, {}),
    'wood':          (128, 128, 1.0, 32, {'reps': (None, 6)}),
    'sand':          (128, 128, 1.0, 24, {'blend': True}),
    'grass':         (128, 128, 1.0, 24, {'blend': True, 'sat': .62, 'bright': .78, 'hue_warm': True}),
    'shopfront':     (256, 128, 2.0, 48, {'whole': True}),
}

def prof(g, axis):
    w, h = g.size
    px = g.load()
    if axis == 0:
        return [sum(px[x, y] for y in range(0, h, 3)) / (h / 3) for x in range(w)]
    return [sum(px[x, y] for x in range(0, w, 3)) / (w / 3) for y in range(h)]

def period(p, lo, hi):
    """fundamental repeat length in [lo,hi] (smallest strong peak, not a multiple); (lag, score)"""
    n = len(p); m = sum(p) / n
    d = [v - m for v in p]
    var = sum(v * v for v in d) or 1
    sc = {}
    for lag in range(lo, min(hi, n // 2)):
        sc[lag] = sum(d[i] * d[i + lag] for i in range(n - lag)) / var * n / (n - lag)
    if not sc: return None, -1
    top = max(sc.values())
    for lag in sorted(sc):
        v = sc[lag]
        if v >= top * .85 and v >= sc.get(lag - 1, -9) and v >= sc.get(lag + 1, -9):
            return lag, v
    return max(sc, key=sc.get), top

def channels(im):
    """luminance, 'redness' (brick vs windows) and edges — a grid shows up in at least one"""
    im = im.convert('RGB')
    r, g, b = im.split()
    red = ImageChops.subtract(r, ImageChops.add(g, b, scale=2.0), offset=128)
    edge = im.convert('L').filter(ImageFilter.FIND_EDGES)
    return [im.convert('L'), red, edge]

def best_period(im, axis, lo, hi):
    # analyse at 1/4 size for speed, scale the lag back up
    small = im.resize((im.size[0] // 4, im.size[1] // 4), Image.BOX)
    best = (None, -1)
    for ch in channels(small):
        lag, s = period(prof(ch, axis), max(2, lo // 4), hi // 4)
        if lag and s > best[1]: best = (lag, s)
    if not best[0]: return best
    # refine the lag at full size around the coarse estimate
    full = prof(im.convert('L'), axis)
    lag4 = best[0] * 4
    lag, s = period(full, max(2, lag4 - 4), lag4 + 5)
    return (lag or lag4), best[1]

def blend_axis(im, axis):
    w, h = im.size
    off = ImageChops.offset(im, w // 2 if axis == 0 else 0, h // 2 if axis == 1 else 0)
    ramp = [int(255 * max(0, 1 - min(1, min(i, (w if axis == 0 else h) - 1 - i) / ((w if axis == 0 else h) * .25))))
            for i in range(w if axis == 0 else h)]
    mask = Image.new('L', (w, h))
    if axis == 0: mask.putdata([ramp[x] for y in range(h) for x in range(w)])
    else: mask.putdata([ramp[y] for y in range(h) for x in range(w)])
    return Image.composite(off, im, mask)

def crop_tile(im, aspect, opt):
    w, h = im.size
    im = im.crop((int(w * .03), int(h * .03), int(w * .97), int(h * .97))); w, h = im.size
    reps = opt.get('reps') or (None, None)
    lens, kinds, info = [None, None], ['b', 'b'], []
    if not opt.get('blend'):
        for axis, size in ((0, w), (1, h)):
            lag, sc = best_period(im, axis, size // 40, size // 2)
            if sc > opt.get('thr', .45) and lag:
                n = reps[axis] or max(1, round(size * .5 / lag))
                n = max(1, min(n, size // lag))
                lens[axis], kinds[axis] = n * lag, 'p'
                info.append(f'{"xy"[axis]}:{n}x{lag}px s={sc:.2f}')
            else:
                info.append(f'{"xy"[axis]}:blend s={sc:.2f}')
    cw, ch = lens
    if cw is None and ch is None:
        if w / h > aspect: cw, ch = int(h * aspect), h
        else: cw, ch = w, int(w / aspect)
    elif cw is None: cw = min(w, int(ch * aspect))
    elif ch is None: ch = min(h, int(cw / aspect))
    x0, y0 = (w - cw) // 2, (h - ch) // 2
    out = im.crop((x0, y0, x0 + cw, y0 + ch))
    if kinds[0] == 'b': out = blend_axis(out, 0)
    if kinds[1] == 'b': out = blend_axis(out, 1)
    return out, ' '.join(info) or 'blended'

def process(name, im):
    ow, oh, aspect, ncol, opt = SPEC[name]
    im = im.convert('RGB')
    if opt.get('whole'):
        w, h = im.size  # keep the whole shop, drop the pavement strip at the bottom
        im = im.crop((int(w * .02), 0, int(w * .98), int(h * .86)))
        info = 'whole'
    else:
        im, info = crop_tile(im, aspect, opt)
    im = im.resize((ow, oh), Image.LANCZOS)
    if opt.get('sat'): im = ImageEnhance.Color(im).enhance(opt['sat'])
    if opt.get('bright'): im = ImageEnhance.Brightness(im).enhance(opt['bright'])
    if opt.get('hue_warm'):  # pull neon green toward a natural olive green
        r, g, b = im.split()
        r = r.point(lambda v: min(255, int(v * 1.25 + 12)))
        b = b.point(lambda v: int(v * .8))
        im = Image.merge('RGB', (r, g, b))
    im = im.quantize(colors=ncol, method=Image.MEDIANCUT, dither=Image.NONE).convert('RGB')
    return im, info

def main():
    only = sys.argv[4:]
    done = []
    for name in SPEC:
        p = os.path.join(RAW, name + '.png')
        o = os.path.join(OUT, name + '.png')
        if not os.path.exists(p): print('missing', name); continue
        if only and name not in only and os.path.exists(o):
            done.append((name, Image.open(o).convert('RGB'))); continue
        im, info = process(name, Image.open(p))
        im.save(o, optimize=True)
        done.append((name, im))
        print(f'{name:14s} {im.size[0]}x{im.size[1]}  {info}  {os.path.getsize(o)} bytes')
    # preview: each tile repeated 2x2 at nearest-neighbour, so seams would show
    cell = 300
    cols = 5; rows = (len(done) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cell, rows * (cell + 22)), (24, 22, 30))
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(done):
        w, h = im.size
        t = Image.new('RGB', (w * 2, h * 2))
        for ox in (0, w):
            for oy in (0, h): t.paste(im, (ox, oy))
        s = min(cell / t.size[0], cell / t.size[1])
        t = t.resize((int(t.size[0] * s), int(t.size[1] * s)), Image.NEAREST)
        x, y = (i % cols) * cell, (i // cols) * (cell + 22)
        sheet.paste(t, (x + (cell - t.size[0]) // 2, y))
        d.text((x + 6, y + cell + 5), name, fill=(240, 220, 255))
    sheet.save(SHEET)

main()
