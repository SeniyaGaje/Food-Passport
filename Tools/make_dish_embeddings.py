#!/usr/bin/env python3
"""
Builds FoodPassport/ML/DishEmbeddings.json from Tools/dishes.json.

The app recognises meals with Apple's MobileCLIP (S1) model, which turns a photo into a list of 512 numbers
(an "embedding"). Its text half turns a sentence such as "a photo of kottu roti" into the same kind of list,
and a photo's embedding is closest to the sentence that describes it. This script runs the text half once,
on a Mac, for every dish description, so the app only needs to ship the image half.

Run it again after editing Tools/dishes.json:

    python3 -m pip install tokenizers coremltools numpy
    python3 Tools/make_dish_embeddings.py

The text model (about 127 MB) is downloaded from Apple's Hugging Face page into Tools/.cache the first time.
Model: MobileCLIP, Apple (CVPR 2024), https://huggingface.co/apple/coreml-mobileclip, Apple Sample Code License.
"""

import json
import os
import urllib.request

import coremltools as ct
import numpy as np
from tokenizers import Tokenizer

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
SOURCE = os.path.join(TOOLS, "dishes.json")
OUTPUT = os.path.join(REPO, "FoodPassport", "ML", "DishEmbeddings.json")

MODEL_NAME = "mobileclip_s1_text.mlpackage"
MODEL_URL = "https://huggingface.co/apple/coreml-mobileclip/resolve/main/" + MODEL_NAME
MODEL_FILES = ["Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"]
MODEL_PATH = os.path.join(TOOLS, ".cache", MODEL_NAME)

# CLIP reads at most 77 tokens: start token, the words, end token, then zeros.
CONTEXT_LENGTH = 77


def download_text_model():
    for file in MODEL_FILES:
        destination = os.path.join(MODEL_PATH, file)
        if os.path.exists(destination):
            continue
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        print("Downloading", file)
        urllib.request.urlretrieve(MODEL_URL + "/" + file, destination)


def tokenize(tokenizer, text):
    """CLIP's tokenizer, padded with zeros to 77 tokens like the original MobileCLIP code."""
    ids = tokenizer.encode(text).ids[:CONTEXT_LENGTH]
    ids[-1] = 49407  # always end with the end-of-text token, even if the text was cut short
    return np.array([ids + [0] * (CONTEXT_LENGTH - len(ids))], dtype=np.int32)


def normalised(vector):
    return vector / np.linalg.norm(vector)


def main():
    download_text_model()
    model = ct.models.MLModel(MODEL_PATH, compute_units=ct.ComputeUnit.CPU_ONLY)
    tokenizer = Tokenizer.from_pretrained("openai/clip-vit-base-patch32")

    with open(SOURCE) as file:
        labels = json.load(file)["labels"]

    output = []
    for label in labels:
        # Averaging several descriptions ("prompt ensembling") gives a steadier embedding than any single one.
        embeddings = [
            normalised(model.predict({"text": tokenize(tokenizer, prompt)})["final_emb_1"][0])
            for prompt in label["prompts"]
        ]
        embedding = normalised(np.mean(embeddings, axis=0))
        output.append({
            "id": label["id"],
            "name": label["name"],
            "cuisine": label["cuisine"],
            "kind": label["kind"],
            "menuNames": label["menuNames"],
            "embedding": [round(float(value), 5) for value in embedding],
        })
        print("  {:<22} {} prompts".format(label["name"], len(label["prompts"])))

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as file:
        json.dump({"model": "MobileCLIP-S1", "dimensions": len(output[0]["embedding"]), "labels": output}, file)
    print("Wrote {} labels to {}".format(len(output), os.path.relpath(OUTPUT, REPO)))


if __name__ == "__main__":
    main()
