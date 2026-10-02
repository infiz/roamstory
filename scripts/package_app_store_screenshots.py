#!/usr/bin/env python3
"""Validate and package both numbered promotional PNG sets for submission."""

from pathlib import Path
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "AppStoreScreenshots"


def main() -> None:
    files = []
    for device, size in (("iPhone", (1284, 2778)), ("iPad", (2064, 2752))):
        paths = sorted((ROOT / device / "Promotional").glob("*.png"))
        if len(paths) != 7:
            raise ValueError(f"Expected seven {device} promotional screenshots")
        for path in paths:
            with Image.open(path) as image:
                if image.size != size or image.mode != "RGB" or image.format != "PNG":
                    raise ValueError(f"Invalid submission image: {path}")
            files.append(path)
    target = ROOT / "RoamStory-AppStore-Submission.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files + [ROOT / "README.md"]:
            archive.write(path, path.relative_to(ROOT))
    print(f"Packaged {len(files)} verified PNGs: {target}")


if __name__ == "__main__":
    main()
