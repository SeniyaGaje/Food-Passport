#!/usr/bin/env python3
"""Make a repeatable 70/15/15 split without sharing an author across sets."""
import collections
import csv
import json
from pathlib import Path
import random
import re

ROOT = Path(__file__).resolve().parent


def author_key(row):
    author = re.sub(r"https?://\S+", "", row["author"].casefold())
    author = re.sub(r"\b(user|own work|from|united states of america)\b", "", author)
    return re.sub(r"[^\w]", "", author) or row["page"]


def main():
    excluded_path = ROOT / "excluded.csv"
    excluded = {x["file"] for x in csv.DictReader(excluded_path.open())} if excluded_path.exists() else set()
    rows = [x for x in csv.DictReader((ROOT / "dataset_log.csv").open()) if x["file"] not in excluded]
    counts = collections.Counter(x["label"] for x in rows)
    dropped = {label: n for label, n in counts.items() if n < 10}
    rows = [row for row in rows if row["label"] not in dropped]
    labels = sorted({row["label"] for row in rows})
    groups = collections.defaultdict(list)
    for row in rows:
        groups[author_key(row)].append(row)
    targets = (0.7, 0.15, 0.15)
    best_score, best = float("inf"), None
    rng = random.Random(38)
    # Large author groups go first; random tie ordering explores several balanced assignments.
    for _ in range(350):
        authors = list(groups)
        rng.shuffle(authors)
        authors.sort(key=lambda author: -len(groups[author]))
        sizes = [collections.Counter() for _ in targets]
        assignment = {}
        for author in authors:
            extra = collections.Counter(x["label"] for x in groups[author])
            costs = []
            for split, target in enumerate(targets):
                cost = sum(((sizes[split][label] + extra[label] - counts[label] * target) ** 2
                            - (sizes[split][label] - counts[label] * target) ** 2) / max(counts[label], 1)
                           for label in labels)
                costs.append(cost + rng.random() * 0.1)
            chosen = min(range(3), key=costs.__getitem__)
            assignment[author] = chosen
            sizes[chosen].update(extra)
        score = sum((sizes[s][label] - counts[label] * targets[s]) ** 2 / counts[label]
                    + (1000 if sizes[s][label] == 0 else 0) for s in range(3) for label in labels)
        if score < best_score:
            best_score, best = score, assignment
    for row in rows:
        row["author_group"] = author_key(row)
        row["split"] = ("train", "validation", "test")[best[row["author_group"]]]
    for label in labels:
        totals = collections.Counter(row["split"] for row in rows if row["label"] == label)
        if any(totals[split] == 0 for split in ("train", "validation", "test")):
            raise SystemExit(f"{label} needs more independent authors before it can be evaluated: {totals}")
        print(label, dict(totals))
    with (ROOT / "split.csv").open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    catalogue = json.loads((ROOT / "catalogue.json").read_text())
    catalogue["classes"] = [x for x in catalogue["classes"] if x["name"] in labels]
    catalogue["droppedClasses"] = dropped
    (ROOT / "training_catalogue.json").write_text(json.dumps(catalogue, indent=2) + "\n")
    print("Dropped (<10 usable photos):", dropped or "none")


if __name__ == "__main__":
    main()
