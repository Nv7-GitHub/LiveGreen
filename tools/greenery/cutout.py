"""Cut hand-drawn art out of its white paper.

Vision's subject mask finds the drawing; paper that is still inside it but connected to the outside (gaps between
leaves) is removed, and a band along every edge is matted against white so no white halo shows on dark backgrounds.
Paper enclosed by ink (white petals, glass highlights) stays opaque.

Usage: cutout.py SOURCE OUT.png MAX_SIDE [--no-vision] [--pad N] [--holes N] [--glass A]
--holes N also clears enclosed paper patches under N source pixels (gaps between leaflets); leave it out to keep
them all, or pass a huge N to clear every one, for art with nothing white in it.
--glass A keeps enclosed paper at alpha A instead, so a glass dome reads as frosted rather than solid white.
--no-vision skips the subject mask, for art Vision finds no subject in (thin grasses, scenes).
Needs Pillow, NumPy and SciPy, and macOS 14 or later for the Vision helper (lift.swift, compiled on first use).
"""
import subprocess, sys, pathlib, tempfile
import numpy as np
from PIL import Image
from scipy import ndimage

src, out, max_side = sys.argv[1], sys.argv[2], int(sys.argv[3])
use_vision = "--no-vision" not in sys.argv
pad = int(sys.argv[sys.argv.index("--pad") + 1]) if "--pad" in sys.argv else 6
holes = int(sys.argv[sys.argv.index("--holes") + 1]) if "--holes" in sys.argv else 0
glass = float(sys.argv[sys.argv.index("--glass") + 1]) if "--glass" in sys.argv else None
lift = pathlib.Path(tempfile.gettempdir()) / "greenery-lift"
if use_vision and not lift.exists():
    subprocess.run(["swiftc", "-O", str(pathlib.Path(__file__).parent / "lift.swift"), "-o", str(lift)], check=True)

rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255
h, w, _ = rgb.shape
if use_vision:
    lifted = pathlib.Path(out).with_suffix(".lift.png")
    subprocess.run([str(lift), src, str(lifted)], check=True, capture_output=True)
    vision = np.asarray(Image.open(lifted).convert("RGBA")).astype(np.float32)[..., 3] / 255
    lifted.unlink()
else:
    vision = np.ones((h, w), np.float32)

# Distance from white paper: 0 on paper, 1 on full-strength ink.
ink = 1 - rgb.min(axis=2)
paper = ink < 0.07
outside = vision < 0.5
labels, _ = ndimage.label(paper)
touching = np.unique(labels[(outside | np.pad(np.zeros((h - 2, w - 2), bool), 1, constant_values=True)) & paper])
exterior = np.isin(labels, touching[touching > 0]) | (outside & paper)
if holes:
    sizes = ndimage.sum(paper, labels, np.arange(1, labels.max() + 1))
    small = np.nonzero(sizes < holes)[0] + 1
    exterior |= np.isin(labels, small) & paper
if not use_vision:
    outside = exterior

clear = exterior | outside
alpha = np.where(clear, 0.0, vision)
band = ndimage.binary_dilation(clear, iterations=4) & ~clear
matte = np.clip((ink - 0.05) / 0.22, 0, 1)
alpha[band] = np.minimum(alpha[band] if use_vision else 1.0, matte[band])
if not use_vision:
    alpha[~clear & ~band] = 1.0

if glass is not None:
    enclosed = paper & ~exterior & ~outside
    enclosed = ndimage.binary_erosion(enclosed, iterations=2)
    alpha[enclosed] = np.minimum(alpha[enclosed], glass)

# Drop dust: opaque islands smaller than a few pixels.
solid = alpha > 0.3
islands, count = ndimage.label(solid)
if count:
    sizes = ndimage.sum(solid, islands, range(1, count + 1))
    tiny = np.isin(islands, np.nonzero(sizes < 25)[0] + 1)
    alpha[tiny] = 0

# Unmultiply white from partly transparent pixels so edges keep the ink colour.
a = alpha[..., None]
color = np.where(a > 0.02, np.clip((rgb - (1 - a)) / np.maximum(a, 0.02), 0, 1), rgb)
color = np.where(a >= 0.999, rgb, color)
rgba = np.dstack([color, alpha])

ys, xs = np.nonzero(alpha > 0.03)
y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, h)
x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, w)
image = Image.fromarray((rgba[y0:y1, x0:x1] * 255).round().astype(np.uint8), "RGBA")
image.thumbnail((max_side, max_side), Image.LANCZOS)
image.save(out, optimize=True)
print(out, image.size, f"{pathlib.Path(out).stat().st_size / 1e6:.2f} MB")
