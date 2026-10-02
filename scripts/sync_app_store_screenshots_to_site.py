#!/usr/bin/env python3
"""Export the iPhone promotional set to RoamStory's apps-pages gallery."""

import argparse
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, default=ROOT.parent / "apps-pages")
    args = parser.parse_args()
    directory = args.site.resolve() / "public/roamstory/images/screenshots"
    if not (args.site / "public/roamstory/index.html").is_file():
        raise ValueError("Expected the apps-pages checkout with a RoamStory product page")
    sources = sorted((ROOT / "AppStoreScreenshots/iPhone/Promotional").glob("*.png"))
    if len(sources) != 7:
        raise ValueError("Expected seven iPhone promotional screenshots")
    directory.mkdir(parents=True, exist_ok=True)
    for source in sources:
        with Image.open(source) as image:
            original = image.convert("RGB")
            original.save(directory / f"{source.stem}.webp", quality=90, method=6)
            for width in (384, 640, 768):
                size = (width, round(original.height * width / original.width))
                original.resize(size, Image.Resampling.LANCZOS).save(
                    directory / f"{source.stem}-w{width}.webp", quality=90, method=6)
    print(f"Exported seven screenshots and responsive variants to {directory}")


if __name__ == "__main__":
    main()
