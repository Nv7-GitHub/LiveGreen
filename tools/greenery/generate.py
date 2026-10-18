"""Generate greenery art with xAI Grok Imagine, two variants per piece, into OUT_DIR.

Usage: python3 tools/greenery/generate.py OUT_DIR [piece ...]
Reads XAI_API_KEY from Secrets.xcconfig at the repo root. Uses curl because python.org builds on macOS often
lack root certificates. Pick the best variant by eye, then cut it out with cutout.py (see pieces.json).
"""
import base64, json, pathlib, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parents[2]
STYLE = ("Loose hand-inked linework with gouache and watercolor washes and grainy colored-pencil texture, slightly "
         "imperfect hand-made lines, muted sage, olive, moss and fern greens with warm ochre, terracotta and soft "
         "blossom-pink accents, vintage storybook naturalist field-journal illustration, not photorealistic, not 3D. "
         "Isolated on a completely plain flat pure white background, no shadow, no frame, no border, no text, no signature.")

key = re.search(r"^XAI_API_KEY\s*=\s*(\S+)", (ROOT / "Secrets.xcconfig").read_text(), re.M).group(1)
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
pieces = json.loads((pathlib.Path(__file__).parent / "pieces.json").read_text())
wanted = set(sys.argv[2:]) or set(pieces)

def generate(name):
    piece = pieces[name]
    body = {"model": "grok-imagine-image-2.0", "prompt": f"{piece['prompt']} {STYLE}", "n": 2,
            "response_format": "b64_json", "aspect_ratio": piece["ratio"], "resolution": "2k"}
    config = f'header = "Authorization: Bearer {key}"\nheader = "Content-Type: application/json"\n'
    raw = subprocess.run(["curl", "-sS", "--max-time", "240", "-K", "-", "--data-binary", json.dumps(body),
                          "https://api.x.ai/v1/images/generations"], input=config.encode(), capture_output=True).stdout
    for index, item in enumerate(json.loads(raw)["data"]):
        (out / f"{name}_{index}.png").write_bytes(base64.b64decode(item["b64_json"]))
    return name

with ThreadPoolExecutor(6) as pool:
    for name in pool.map(generate, sorted(wanted)):
        print("generated", name)
