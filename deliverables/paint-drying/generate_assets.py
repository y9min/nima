#!/usr/bin/env python3
"""Build the masked dry-paint overlay used by the Lottie composition."""

from pathlib import Path
from PIL import Image
import colorsys


ROOT = Path(__file__).resolve().parent
SOURCE = Path("/var/folders/t_/tv6wr7ln7hx2pb_ztv8cc9v00000gp/T/codex-clipboard-5a420329-5cc1-4e31-8f2d-1682d8441e49.png")
ASSETS = ROOT / "assets"


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    image = Image.open(SOURCE).convert("RGBA")
    image.save(ASSETS / "nima_paint_reference.png", optimize=True)

    # Only the fence may dry. This source-space region deliberately stops above
    # the bucket, brush and ground puddles, which must retain their original colour.
    dry_rgb = (0x62, 0x95, 0x80)
    pixels = image.load()
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    output = overlay.load()
    recoloured = 0

    for y in range(min(915, image.height)):
        for x in range(175, min(990, image.width)):
            # The bucket overlaps the lower-left fence. Exclude only the bucket's
            # actual upper bounds; a broader rectangle leaves a fresh-green fence
            # strip visible above and to the right of it in the dry state.
            if x < 285 and y >= 735:
                continue
            r, g, b, a = pixels[x, y]
            if a < 8:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            # Reference greens fall around 148–165 degrees. Keep the threshold
            # narrow enough to avoid the cream wood and neutral hardware.
            hue_degrees = h * 360
            if 135 <= hue_degrees <= 175 and s >= 0.28 and g > r * 1.12 and g > b * 1.03:
                # Preserve the original painted wood's subtle shading and texture.
                source_luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                reference_luma = 0.2126 * 0 + 0.7152 * 128 + 0.0722 * 83
                # Compress the tonal range so the dry state keeps wood shading but
                # loses the source artwork's glossy highlight peaks.
                factor = max(0.72, min(1.08, source_luma / reference_luma))
                nr = min(255, round(dry_rgb[0] * factor))
                ng = min(255, round(dry_rgb[1] * factor))
                nb = min(255, round(dry_rgb[2] * factor))
                output[x, y] = (nr, ng, nb, a)
                recoloured += 1

    overlay.save(ASSETS / "nima_paint_dry_overlay_v2.png", optimize=True)
    print(f"Created assets at {image.size[0]}x{image.size[1]}; recoloured {recoloured:,} pixels")


if __name__ == "__main__":
    main()
