#!/usr/bin/env python3
"""
Measures how well the meal recogniser names real photos.

It downloads the labelled photos listed in Tools/evaluation_photos.json (from Wikimedia Commons), runs the app's
own MobileCLIP image model on each one, and picks dishes with the same rules as MealClassifier in the app.
Then it prints the top-1 score (the first suggestion is right) and the top-3 score (the right one is in the
three suggestions the student sees).

    python3 -m pip install coremltools numpy pillow
    python3 Tools/evaluate_recognizer.py                 # scores FoodPassport/ML/DishEmbeddings.json
    python3 Tools/evaluate_recognizer.py other.json      # scores another labels file, e.g. an older one

Photos are saved in Tools/.cache/evaluation the first time, so later runs are quick.
"""

import io
import json
import os
import sys
import urllib.request

import coremltools as ct
import numpy as np
from PIL import Image, ImageOps

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
PHOTOS = os.path.join(TOOLS, "evaluation_photos.json")
CACHE = os.path.join(TOOLS, ".cache", "evaluation")
IMAGE_MODEL = os.path.join(REPO, "FoodPassport", "ML", "MobileCLIPImageEncoder.mlpackage")
USER_AGENT = {"User-Agent": "FoodPassport-student-project/1.0"}

# The same numbers as MealClassifier in the app.
LOGIT_SCALE = 100
NOT_MEAL_THRESHOLD = 0.5


def download(photo, index):
    path = os.path.join(CACHE, f"{index:03d}.jpg")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        request = urllib.request.Request(photo["image"], headers=USER_AGENT)
        with urllib.request.urlopen(request, timeout=60) as response, open(path, "wb") as file:
            file.write(response.read())
    return path


def prepare(path):
    """Shortest side to 256, then the middle 256 x 256, like Vision's .centerCrop in the app."""
    image = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    width, height = image.size
    scale = 256 / min(width, height)
    image = image.resize((max(256, round(width * scale)), max(256, round(height * scale))), Image.BICUBIC)
    width, height = image.size
    left, top = (width - 256) // 2, (height - 256) // 2
    return image.crop((left, top, left + 256, top + 256))


def suggestions(photo_embedding, label_embeddings, labels):
    """The app's MealClassifier.classify (without the menu boost): up to three dish or drink names."""
    logits = LOGIT_SCALE * (label_embeddings @ photo_embedding)
    chances = np.exp(logits - logits.max())
    chances /= chances.sum()
    ranked = np.argsort(-chances)
    best = labels[ranked[0]]
    if best["kind"] not in ("dish", "drink") and chances[ranked[0]] >= NOT_MEAL_THRESHOLD:
        return []
    return [labels[i]["name"] for i in ranked if labels[i]["kind"] in ("dish", "drink")][:3]


def main():
    labels_file = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "FoodPassport", "ML", "DishEmbeddings.json")
    labels = json.load(open(labels_file))["labels"]
    label_embeddings = np.array([label["embedding"] for label in labels])
    photos = json.load(open(PHOTOS))["photos"]
    model = ct.models.MLModel(IMAGE_MODEL, compute_units=ct.ComputeUnit.CPU_ONLY)

    # results[set][group] = [photos, top-1 right, top-3 right]
    results = {}
    for index, photo in enumerate(photos):
        output = model.predict({"image": prepare(download(photo, index))})["final_emb_1"]
        embedding = np.array(output).reshape(-1)
        embedding /= np.linalg.norm(embedding)
        top = suggestions(embedding, label_embeddings, labels)

        group = photo.get("group", "All")
        for key in (group, "All"):
            row = results.setdefault(photo["set"], {}).setdefault(key, [0, 0, 0])
            row[0] += 1
            row[1] += top[:1] == [photo["label"]]
            row[2] += photo["label"] in top

    print(f"Scoring {os.path.relpath(labels_file, REPO)} on {len(photos)} photos\n")
    for photo_set in ("test", "tuning", "check"):
        for group, (count, top1, top3) in results.get(photo_set, {}).items():
            print(f"{photo_set:7} {group:16} {count:4} photos   top-1 {100 * top1 / count:5.1f}%   top-3 {100 * top3 / count:5.1f}%")
    print("\n'test' is the honest score: those photos weren't used while writing the descriptions.")


if __name__ == "__main__":
    main()
