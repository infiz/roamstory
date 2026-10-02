#!/usr/bin/env python3
"""Build RoamStory's 6.5-inch promotional screenshots in the VocabHero style."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent.parent
SCREENSHOT_ROOT = ROOT / "AppStoreScreenshots"
RAW_DIRECTORY = SCREENSHOT_ROOT / "iPhone" / "Raw"
OUTPUT_DIRECTORY = SCREENSHOT_ROOT / "iPhone" / "Promotional"
BACKGROUND_PATH = SCREENSHOT_ROOT / "Assets" / "promo-background.png"

CANVAS_SIZE = (1284, 2778)
SCREEN_SIZE = (1028, 2224)
SCREEN_LEFT = (CANVAS_SIZE[0] - SCREEN_SIZE[0]) // 2
SCREEN_TOP = 544
SCREEN_RADIUS = 58

TITLE_FONT_PATH = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
EYEBROW_FONT_PATH = Path("/System/Library/Fonts/SFNS.ttf")


@dataclass(frozen=True)
class Promotion:
    output_name: str
    source_name: str
    title: tuple[str, ...]


PROMOTIONS = (
    Promotion("01-trips.png", "01-trips.png", ("Every journey.", "A story worth keeping.")),
    Promotion("02-organize.png", "02-organize.png", ("One trip.", "So many stories.")),
    Promotion("03-write.png", "03-write.png", ("Write the moments", "you want to remember.")),
    Promotion("04-photo.png", "04-photo.png", ("Your words.", "Your favorite photos.")),
    Promotion("05-gallery.png", "05-gallery.png", ("Bring your memories", "together in a gallery.")),
    Promotion("06-map.png", "06-map.png", ("Keep the story", "connected to the place.")),
    Promotion("07-export.png", "07-export.png", ("A whole trip.", "Or just one chapter.")),
)


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def centered_text(
    draw: ImageDraw.ImageDraw,
    y: int,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: str,
) -> None:
    bounds = draw.textbbox((0, 0), text, font=font)
    width = bounds[2] - bounds[0]
    if width > CANVAS_SIZE[0] - 100:
        raise ValueError(f"Headline exceeds the safe horizontal margin: {text}")
    draw.text(((CANVAS_SIZE[0] - width) / 2, y), text, font=font, fill=fill)


def title_layer(lines: tuple[str, ...]) -> Image.Image:
    layer = Image.new("RGBA", (CANVAS_SIZE[0], 504), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    eyebrow_font = ImageFont.truetype(str(EYEBROW_FONT_PATH), 27)
    title_font = ImageFont.truetype(str(TITLE_FONT_PATH), 89)

    centered_text(draw, 35, "R O A M S T O R Y", eyebrow_font, "#007A9B")
    for index, line in enumerate(lines):
        centered_text(draw, 105 + index * 105, line, title_font, "#17141F")
    return layer


def rounded_screen(source_path: Path) -> Image.Image:
    source = Image.open(source_path)
    if source.size != CANVAS_SIZE:
        raise ValueError(f"Expected a native {CANVAS_SIZE} capture: {source_path}")
    screen = source.convert("RGB").resize(
        SCREEN_SIZE, Image.Resampling.LANCZOS
    )
    mask = Image.new("L", SCREEN_SIZE, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, SCREEN_SIZE[0], SCREEN_SIZE[1]),
        radius=SCREEN_RADIUS,
        fill=255,
    )
    result = screen.convert("RGBA")
    result.putalpha(mask)
    return result


def screen_shadow() -> Image.Image:
    padding = 60
    shadow = Image.new(
        "RGBA", (SCREEN_SIZE[0] + padding * 2, SCREEN_SIZE[1] + padding * 2)
    )
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle(
        (padding, padding - 24, padding + SCREEN_SIZE[0], padding - 24 + SCREEN_SIZE[1]),
        radius=SCREEN_RADIUS,
        fill=(23, 20, 31, 72),
    )
    return shadow.filter(ImageFilter.GaussianBlur(28))


def generate(promotion: Promotion, background: Image.Image, shadow: Image.Image) -> Path:
    source_path = RAW_DIRECTORY / promotion.source_name
    if not source_path.exists():
        raise FileNotFoundError(f"Missing raw screenshot: {source_path}")

    composition = background.copy().convert("RGBA")
    composition.alpha_composite(title_layer(promotion.title), (0, 0))
    composition.alpha_composite(shadow, (SCREEN_LEFT - 60, SCREEN_TOP - 36))
    composition.alpha_composite(rounded_screen(source_path), (SCREEN_LEFT, SCREEN_TOP))

    output_path = OUTPUT_DIRECTORY / promotion.output_name
    composition.convert("RGB").save(output_path, "PNG", compress_level=9)
    return output_path


def main(contact_name: str = "contact-sheet.png") -> None:
    if not BACKGROUND_PATH.exists():
        raise FileNotFoundError(f"Missing promotional background: {BACKGROUND_PATH}")

    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    background = cover(Image.open(BACKGROUND_PATH).convert("RGB"), CANVAS_SIZE)
    shadow = screen_shadow()

    for promotion in PROMOTIONS:
        output_path = generate(promotion, background, shadow)
        print(f"Created {output_path.relative_to(ROOT)}")

    thumbnail_width = 257
    thumbnail_height = round(thumbnail_width * CANVAS_SIZE[1] / CANVAS_SIZE[0])
    contact = Image.new("RGB", (thumbnail_width * len(PROMOTIONS), thumbnail_height), "white")
    for index, promotion in enumerate(PROMOTIONS):
        with Image.open(OUTPUT_DIRECTORY / promotion.output_name) as result:
            assert result.size == CANVAS_SIZE and result.mode == "RGB"
            contact.paste(result.resize((thumbnail_width, thumbnail_height), Image.Resampling.LANCZOS),
                          (index * thumbnail_width, 0))
    contact.save(SCREENSHOT_ROOT / contact_name)


if __name__ == "__main__":
    main()
