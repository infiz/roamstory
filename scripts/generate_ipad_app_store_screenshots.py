#!/usr/bin/env python3
"""Apply RoamStory's shared promotional style to native 13-inch iPad captures."""

from PIL import Image, ImageDraw, ImageFont

import generate_iphone_app_store_screenshots as compositor


def title_layer(lines: tuple[str, ...]) -> Image.Image:
    layer = Image.new("RGBA", (2064, 520), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    eyebrow = ImageFont.truetype(str(compositor.EYEBROW_FONT_PATH), 31)
    title = ImageFont.truetype(str(compositor.TITLE_FONT_PATH), 112)
    compositor.centered_text(draw, 42, "R O A M S T O R Y", eyebrow, "#007A9B")
    for index, line in enumerate(lines):
        compositor.centered_text(draw, 132 + index * 130, line, title, "#17141F")
    return layer


def main() -> None:
    compositor.CANVAS_SIZE = (2064, 2752)
    compositor.SCREEN_SIZE = (1620, 2160)
    compositor.SCREEN_LEFT = 222
    compositor.SCREEN_TOP = 560
    compositor.SCREEN_RADIUS = 48
    compositor.RAW_DIRECTORY = compositor.SCREENSHOT_ROOT / "iPad/Raw"
    compositor.OUTPUT_DIRECTORY = compositor.SCREENSHOT_ROOT / "iPad/Promotional"
    compositor.title_layer = title_layer
    compositor.main("contact-sheet-ipad.png")


if __name__ == "__main__":
    main()
