#!/usr/bin/env python3
"""Record an obvious bad photo: python3 exclude.py Images/kottu/file.jpg 'wrong dish'."""
import argparse
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent
# Arguments: the photo's path and why it's being removed.
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("file")
parser.add_argument("reason")
args = parser.parse_args()
path = ROOT / "excluded.csv"
# Load the list, replacing any earlier entry for the same photo.
rows = list(csv.DictReader(path.open())) if path.exists() else []
rows = [row for row in rows if row["file"] != args.file]
rows.append({"file": args.file, "reason": args.reason})
# Write the list back; split_dataset.py leaves these photos out.
with path.open("w", newline="") as output:
    writer = csv.DictWriter(output, fieldnames=["file", "reason"], lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
