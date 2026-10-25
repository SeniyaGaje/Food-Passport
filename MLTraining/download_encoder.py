#!/usr/bin/env python3
"""Download Apple's frozen S0 encoder, checking the published file hashes."""
import hashlib
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "FoodPassport/ML/MobileCLIPImageEncoder.mlpackage"
REVISION = "3e0a7bfb9fe83da8a3efaa3fd8f7df24214bb947"
FILES = {
    "Manifest.json": "fe07dde983dae92c1799132816ce55f9ff8487f2681b530abf7222025aa27fa4",
    "Data/com.apple.CoreML/model.mlmodel": "2c1afa132c41c6535817cc67894bd7484bc2cbd084ed5e2f12b24f611af17591",
    "Data/com.apple.CoreML/weights/weight.bin": "87d8f63997bbd2f38ba7defeaaa2c571928bdece56aa9629542198b3ce906ed6",
}
for name, expected in FILES.items():
    destination = DESTINATION / name
    data = destination.read_bytes() if destination.exists() else b""
    if not data or (expected and hashlib.sha256(data).hexdigest() != expected):
        url = f"https://huggingface.co/apple/coreml-mobileclip/resolve/{REVISION}/mobileclip_s0_image.mlpackage/{name}"
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read()
        if expected and hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit("Hash mismatch: " + name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    print("Verified", name)
