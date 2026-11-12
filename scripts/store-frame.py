#!/usr/bin/env python3
"""Puts a caption above each raw simulator screenshot. Called by scripts/store-screenshots.sh.

Usage: store-frame.py <folder of raw NN-screen.png> <output folder>
Output: 1320x2868 PNG, RGB with no alpha, which is what App Store Connect takes for iPhone 6.9".
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = (1320, 2868)
NIGHT = (10, 12, 11)      # dlNight, the app's background
TEXT = (236, 233, 226)    # dlText
HAIRLINE = (52, 56, 54)
FONT = Path(__file__).resolve().parent.parent / "DLChat/Design/Fonts/Manrope.ttf"

# One caption per screen, in store order. "\n" is the line break.
CAPTIONS = {
    "compose": "Turn a message into\nwords to say",
    "readout": "Read the words out\nover a radio",
    "tones": "Or play the message\nas sound",
    "qr": "Up close, show\na QR code",
    "chat": "Chat online when\nthe internet works",
    "safety": "Hold one button to\nwipe everything",
}


def frame(raw: Path, out: Path) -> None:
    screen = raw.stem.split("-", 1)[1]
    shot = Image.open(raw).convert("RGB")
    assert shot.size == SIZE, f"{raw.name} is {shot.size}, expected {SIZE}"
    canvas = Image.new("RGB", SIZE, NIGHT)
    draw = ImageDraw.Draw(canvas)

    font = ImageFont.truetype(str(FONT), 96)
    font.set_variation_by_axes([700])
    draw.multiline_text((SIZE[0] // 2, 300), CAPTIONS[screen], font=font, fill=TEXT,
                        anchor="mm", align="center", spacing=24)
    left, top, right, bottom = draw.multiline_textbbox((SIZE[0] // 2, 300), CAPTIONS[screen], font=font,
                                                       anchor="mm", align="center", spacing=24)
    assert left >= 60 and right <= SIZE[0] - 60 and bottom <= 500, f"caption for {screen} does not fit"

    # The screen at 78%, rounded like a phone, running off the bottom edge.
    w = int(SIZE[0] * 0.78)
    h = int(SIZE[1] * 0.78)
    small = shot.resize((w, h), Image.LANCZOS)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=96, fill=255)
    x, y = (SIZE[0] - w) // 2, 560
    canvas.paste(small, (x, y), mask)
    draw.rounded_rectangle((x - 3, y - 3, x + w + 2, y + h + 2), radius=99, outline=HAIRLINE, width=3)

    canvas.save(out / f"{raw.stem}.png", optimize=True)


def main() -> None:
    raw_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    raws = sorted(raw_dir.glob("[0-9][0-9]-*.png"))
    assert len(raws) == len(CAPTIONS), f"expected {len(CAPTIONS)} screenshots, found {len(raws)}"
    for raw in raws:
        frame(raw, out_dir)
        print(out_dir / raw.name)


if __name__ == "__main__":
    main()
