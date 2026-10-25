#!/usr/bin/env python3
"""Download the small object detector used to locate separate meal items."""
import hashlib
from pathlib import Path
import urllib.request

destination = Path(__file__).resolve().parent.parent / "FoodPassport/ML/MealObjectDetector.mlmodel"
expected = "73406178d0f5793d0d5d1e38274acd146a744c2245c9b63a11998a5015925dda"
url = "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyFP16.mlmodel"
data = destination.read_bytes() if destination.exists() else b""
if hashlib.sha256(data).hexdigest() != expected:
    with urllib.request.urlopen(url, timeout=90) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise SystemExit("The detector download did not match its expected hash")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
print("Verified YOLOv3-tiny FP16")
