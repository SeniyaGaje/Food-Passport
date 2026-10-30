#!/usr/bin/env python3
"""Collect a small, credited dataset. Uses only the Python standard library."""
import argparse
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import csv
import hashlib
import html
import json
import itertools
from pathlib import Path
import re
import socket
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent
# A clear User-Agent, as the Wikimedia API asks for.
HEADERS = {"User-Agent": "FoodPassport/1.0 (educational image classification; Wikimedia/Openverse)"}
# The columns of dataset_log.csv: what the photo shows, where it came from and its licence.
FIELDS = ["label", "file", "source", "title", "page", "author", "licence", "licence_url", "sha256"]
# Shared by the download threads, so requests stay at least 0.35 s apart.
LAST_REQUEST = 0
REQUEST_LOCK = threading.Lock()
# Words a file title must contain, so search results for the wrong dish are dropped.
KEYWORDS = {
    "kottu": ["kottu", "kotthu", "kothu"], "hoppers": ["appam", "hopper"],
    "string-hoppers": ["idiyappam", "idiappam", "string hopper", "noolputtu"],
    "rice-curry": ["rice", "sri lankan meal"], "dosa": ["dosa", "dosai"],
    "fried-rice": ["fried rice", "nasi goreng", "chahan"], "pizza": ["pizza"],
    "burger": ["burger"], "coffee": ["coffee", "cappuccino", "espresso", "latte"],
    "tea": ["tea", "chai"], "cake-dessert": ["cake", "cupcake", "cheesecake", "brownie"]
}


# Downloads a URL politely: rate-limited, retrying busy or failed requests with a growing wait.
def fetch(url, retries=4):
    global LAST_REQUEST
    for attempt in range(retries):
        with REQUEST_LOCK:
            time.sleep(max(0, 0.35 - (time.monotonic() - LAST_REQUEST)))
            LAST_REQUEST = time.monotonic()
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=8) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504):
                raise
            time.sleep(min(30, max(float(error.headers.get("Retry-After", 0)), 2 ** attempt)))
        except (OSError, TimeoutError):
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)
    raise OSError("Request still unavailable after retries")


# Calls a JSON web API with query parameters.
def api(url, **params):
    return json.loads(fetch(url + "?" + urllib.parse.urlencode(params)))


# Removes HTML tags from author names.
def clean(value):
    return html.unescape(re.sub("<[^>]+>", "", value)).strip()


# Looks up the licence and author of Commons files, 20 at a time.
def commons(titles):
    for start in range(0, len(titles), 20):
        try:
            data = api("https://commons.wikimedia.org/w/api.php", action="query", format="json",
                       prop="imageinfo", iiprop="url|extmetadata", iiurlwidth=640,
                       titles="|".join(titles[start:start + 20]))
        except OSError as error:
            print("Commons batch skipped:", error, flush=True)
            continue
        for page in data.get("query", {}).get("pages", {}).values():
            info = page.get("imageinfo", [{}])[0]
            meta = info.get("extmetadata", {})
            licence = meta.get("LicenseShortName", {}).get("value", "")
            # Keep only open licences: CC BY, CC BY-SA, CC0 or public domain.
            if not (licence.startswith("CC BY") or licence in ("CC0", "Public domain")):
                continue
            title = page["title"]
            if not title.lower().endswith((".jpg", ".jpeg", ".png")):
                continue
            yield dict(source="Wikimedia Commons", title=title, page=info.get("descriptionurl", ""),
                       author=clean(meta.get("Artist", {}).get("value", "")), licence=licence,
                       licence_url=meta.get("LicenseUrl", {}).get("value", ""),
                       url=info.get("thumburl", info.get("url")))


# Yields candidate photos for one class: Wikimedia Commons first, then Openverse.
def candidates(entry):
    titles = []
    category_lists = []
    # Files listed in the class's Commons categories.
    for category in entry["categories"]:
        data = api("https://commons.wikimedia.org/w/api.php", action="query", format="json",
                   list="categorymembers", cmtitle="Category:" + category, cmtype="file", cmlimit=100)
        category_lists.append([x["title"] for x in data.get("query", {}).get("categorymembers", [])])
    for row in itertools.zip_longest(*category_lists):
        titles += [title for title in row if title]
    # Files found by the class's search phrases.
    for query in entry["queries"]:
        data = api("https://commons.wikimedia.org/w/api.php", action="query", format="json",
                   list="search", srsearch=query + " filetype:bitmap", srnamespace=6,
                   srlimit=15 if entry["id"] == "other" else 40)
        titles += [x["title"] for x in data.get("query", {}).get("search", [])]
    words = KEYWORDS.get(entry["id"], [])
    # Drop repeated titles and titles without the class's keywords.
    titles = [title for title in dict.fromkeys(titles) if not words or any(word in title.casefold() for word in words)]
    yield from commons(titles)
    # Openverse search, limited to open licences.
    for query in entry["queries"]:
        for page in (1, 2):
            try:
                data = api("https://api.openverse.org/v1/images/", q=query, page_size=20, page=page,
                           license="by,by-sa,cc0,pdm", mature="false")
                for item in data.get("results", []):
                    # Wikimedia is already covered above; Flickr thumbnails are small enough for training.
                    if item.get("source") == "wikimedia":
                        continue
                    if words and not any(word in item["title"].casefold() for word in words):
                        continue
                    url = item["url"]
                    if "staticflickr.com" in url:
                        url = re.sub(r"_[a-z]\.jpg$", "_z.jpg", url)
                    yield dict(source="Openverse/" + item["source"], title=item["title"],
                               page=item["foreign_landing_url"], author=item.get("creator") or "Unknown",
                               licence="CC " + item["license"].upper() + " " + (item.get("license_version") or ""),
                               licence_url=item["license_url"], url=url)
            except (OSError, ValueError) as error:
                print("Openverse query skipped:", query, error, flush=True)


def downloads(entry, pages, blocked):
    """At most three downloads in flight; requests still share one rate limit."""
    source = iter(candidates(entry))
    pending = {}
    finished = False
    with ThreadPoolExecutor(max_workers=3) as pool:
        while pending or not finished:
            while len(pending) < 3 and not finished:
                try:
                    photo = next(source)
                except StopIteration:
                    finished = True
                    break
                # Skip photos already in the dataset and the app's own photos.
                if photo["page"] in pages or photo["title"].replace("_", " ").casefold() in blocked:
                    continue
                if not photo["url"] or not photo["author"]:
                    continue
                pending[pool.submit(fetch, photo["url"], 2)] = photo
            if not pending:
                continue
            done, _ = wait(pending, return_when=FIRST_COMPLETED)
            for future in done:
                photo = pending.pop(future)
                try:
                    yield photo, future.result()
                except (OSError, ValueError) as error:
                    print("  Skipped:", photo["title"], str(error)[:100], flush=True)


# Collects photos for each class until it reaches its target count.
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--other", type=int, default=150)
    parser.add_argument("--labels", nargs="*")
    parser.add_argument("--ipv4", action="store_true", help="For networks with broken IPv6")
    args = parser.parse_args()
    # --ipv4 forces IPv4, for networks with broken IPv6.
    if args.ipv4:
        getaddrinfo = socket.getaddrinfo
        socket.getaddrinfo = lambda host, port, *a, **kw: getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)

    # The ledger of every photo collected so far, and the ones excluded after review.
    log = ROOT / "dataset_log.csv"
    rows = list(csv.DictReader(log.open())) if log.exists() else []
    excluded_path = ROOT / "excluded.csv"
    excluded = {x["file"] for x in csv.DictReader(excluded_path.open())} if excluded_path.exists() else set()
    # Hashes and pages seen before, so the same photo is never added twice.
    hashes = {row["sha256"] for row in rows}
    pages = {row["page"] for row in rows}
    # App illustrations must remain unseen, including resized versions of the originals.
    credits = (ROOT.parent / "PHOTO_CREDITS.md").read_text()
    blocked = {urllib.parse.unquote(x).replace("_", " ").casefold()
               for x in re.findall(r"https://commons.wikimedia.org/wiki/(File:[^)]+(?:\)[^)]*)?)\)", credits)}
    blocked_names = ["Kottu Roti (mit Meeresfrüchten).jpg", "Vegetarian thali-MB-42.jpg",
                     "Fried rice at restaurant Long Wall.jpg", "Appam by Connie Ma.jpg",
                     "Pasta Carbonara at Gete Deli in May 2024 close up.jpg", "Traditional Jaffna Rice and Curry.JPG",
                     "Tach tra o sri lanka.jpg", "Kottu.jpg", "Masala dosa 01.jpg", "Chicken makhani.jpg"]
    blocked.update(("file:" + x).replace("_", " ").casefold() for x in blocked_names)
    with log.open("a", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=FIELDS, lineterminator="\n")
        if not rows:
            writer.writeheader()
        # Each class listed in catalogue.json.
        for entry in json.loads((ROOT / "catalogue.json").read_text())["classes"]:
            label = entry["name"]
            if args.labels and entry["id"] not in args.labels:
                continue
            # How many usable photos this class already has, and how many it needs.
            count = sum(row["label"] == label and row["file"] not in excluded for row in rows)
            target = args.other if entry["id"] == "other" else args.limit
            if count >= target:
                continue
            print(f"Collecting {label}: {count}/{target}", flush=True)
            folder = ROOT / "Images" / entry["id"]
            folder.mkdir(parents=True, exist_ok=True)
            for photo, data in downloads(entry, pages, blocked):
                if count >= target:
                    break
                try:
                    photo.pop("url")
                    # Only real JPEG or PNG files are kept.
                    if not (data.startswith(b"\xff\xd8\xff") or data.startswith(b"\x89PNG")):
                        continue
                    # Skip exact duplicates, by file hash.
                    digest = hashlib.sha256(data).hexdigest()
                    if digest in hashes:
                        continue
                    # Name the file after its hash and record its credit in the ledger.
                    path = folder / (digest[:16] + (".png" if data.startswith(b"\x89PNG") else ".jpg"))
                    path.write_bytes(data)
                    row = dict(photo, label=label, file=str(path.relative_to(ROOT)), sha256=digest)
                    writer.writerow(row)
                    output.flush()
                    rows.append(row)
                    hashes.add(digest)
                    pages.add(photo["page"])
                    count += 1
                    if count % 10 == 0:
                        print(f"  {label}: {count}", flush=True)
                except (OSError, ValueError) as error:
                    print("  Skipped:", photo["title"], str(error)[:100], flush=True)
            print(f"Finished {label}: {count} photos", flush=True)


if __name__ == "__main__":
    main()
