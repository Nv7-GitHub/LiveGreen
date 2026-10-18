"""Put a cut-out PNG into the asset catalog as Greenery/NAME, reduced to a 256-colour palette (about a quarter of
the size; the grain hides any banding).

Usage: install.py CUT.png NAME
"""
import json, pathlib, sys
from PIL import Image

source, name = sys.argv[1], sys.argv[2]
folder = pathlib.Path(__file__).resolve().parents[2] / "LiveGreen/Resources/Assets.xcassets/Greenery" / f"{name}.imageset"
folder.mkdir(parents=True, exist_ok=True)
image = Image.open(source).convert("RGBA")
image.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(
    folder / f"{name}.png", optimize=True)
(folder / "Contents.json").write_text(json.dumps({
    "images": [{"filename": f"{name}.png", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
}, indent=2) + "\n")
print(folder / f"{name}.png", image.size)
