#!/usr/bin/env python3
"""Render the saved photo-based journey and verify its retained photo assets."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "AppStoreScreenshots/Assets/Brazil2026"


def main() -> None:
    journey = json.loads((ASSETS / "journey.json").read_text())
    provenance = json.loads((ASSETS / "photos.json").read_text())
    filenames = set()
    for photo in provenance["photos"]:
        path = ASSETS / "Photos" / photo["file"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != photo["sha256"]:
            raise ValueError(f"Retained photo changed: {path}")
        filenames.add(photo["file"])
    chapters = {chapter["key"] for chapter in journey["sections"]}
    if not set(journey["screenshotSections"].values()) <= chapters:
        raise ValueError("Screenshot routing refers to a missing chapter")
    lines = [f'# {journey["title"]}', "", journey["subtitle"], "",
             f'{journey["startDate"]} – {journey["endDate"]}', "",
             f'> {journey["editorialNote"]}', ""]
    for chapter in journey["sections"]:
        lines += [f'## {chapter["title"]}', "", f'{chapter["date"]} · {chapter["placeName"]}', ""]
        for block in chapter["blocks"]:
            if block.get("title"):
                lines += [f'### {block["title"]}', ""]
            if block.get("text"):
                prefix = "> " if block["type"] == "quote" else ""
                lines += [prefix + block["text"], ""]
            if block["type"] == "map":
                lines += [f'**Map:** {block["mapPlaceName"]} ({block["mapLatitude"]}, {block["mapLongitude"]})',
                          "", block["mapDescription"], ""]
            for photo in block.get("photos", []):
                if photo["file"] not in filenames:
                    raise ValueError(f'Missing photo provenance: {photo["file"]}')
                lines += [f'![{photo["caption"]}](Photos/{photo["file"]})', "", photo["caption"], ""]
    (ASSETS / "journey.md").write_text("\n".join(lines))
    print(f'Rendered {len(journey["sections"])} chapters; verified {len(filenames)} photos.')


if __name__ == "__main__":
    main()
