"""Split a cut-out sheet of separate leaves into one PNG per leaf, top row first.

Usage: split.py SHEET.png PREFIX MAX_SIDE  (writes PREFIX0.png, PREFIX1.png, …)
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

sheet, prefix, side = Image.open(sys.argv[1]).convert("RGBA"), sys.argv[2], int(sys.argv[3])
solid = np.asarray(sheet)[..., 3] > 20
# Dilate so a leaf and its own thin stem count as one piece.
labels, count = ndimage.label(ndimage.binary_dilation(solid, iterations=6))
boxes = ndimage.find_objects(labels)
sizes = ndimage.sum(solid, labels, range(1, count + 1))
keep = sorted((i for i in range(count) if sizes[i] > 2000), key=lambda i: (boxes[i][0].start // 300, boxes[i][1].start))
for number, i in enumerate(keep):
    ys, xs = boxes[i]
    crop = sheet.crop((xs.start, ys.start, xs.stop, ys.stop))
    mask = Image.fromarray(((labels[ys, xs] == i + 1) * 255).astype(np.uint8))
    leaf = Image.new("RGBA", crop.size)
    leaf.paste(crop, (0, 0), mask)
    leaf.thumbnail((side, side), Image.LANCZOS)
    leaf.save(f"{prefix}{number}.png", optimize=True)
    print(f"{prefix}{number}.png", leaf.size)
