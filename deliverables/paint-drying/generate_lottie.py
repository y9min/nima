#!/usr/bin/env python3
"""Generate the production Lottie JSON using only iOS-safe core features."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
FPS = 30
END = 1800
FRESH = [0.0, 128 / 255, 83 / 255, 1]
DRY = [98 / 255, 149 / 255, 128 / 255, 1]


def linear_keyframes(start, end, start_value, end_value):
    return {
        "a": 1,
        "k": [
            {"t": start, "s": start_value, "e": end_value, "o": {"x": [0.167], "y": [0.167]}, "i": {"x": [0.833], "y": [0.833]}},
            {"t": end, "s": end_value},
        ],
    }


def static(value):
    return {"a": 0, "k": value}


def transform(position=(0, 0), anchor=(0, 0), scale=(100, 100), opacity=100):
    return {
        "o": static(opacity), "r": static(0), "p": static(list(position)),
        "a": static(list(anchor)), "s": static(list(scale)),
    }


def image_layer(index, name, ref_id, opacity):
    return {
        "ddd": 0, "ind": index, "ty": 2, "nm": name, "refId": ref_id,
        "sr": 1, "ks": {
            "o": opacity, "r": static(0), "p": static([512, 512, 0]),
            "a": static([782, 528, 0]), "s": static([64, 64, 100]),
        },
        "ao": 0, "ip": 0, "op": END, "st": 0, "bm": 0,
    }


def highlight_layer(index, name, points):
    path = {"i": [[0, 0] for _ in points], "o": [[0, 0] for _ in points], "v": points, "c": False}
    return {
        "ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1,
        "ks": {
            "o": {"a": 1, "k": [
                {"t": 0, "s": [6], "e": [2], "o": {"x": [0.167], "y": [0.167]}, "i": {"x": [0.833], "y": [0.833]}},
                {"t": 900, "s": [2], "e": [0], "o": {"x": [0.167], "y": [0.167]}, "i": {"x": [0.833], "y": [0.833]}},
                {"t": 1500, "s": [0]},
            ]},
            "r": static(0), "p": static([0, 0, 0]), "a": static([0, 0, 0]), "s": static([100, 100, 100]),
        },
        "shapes": [
            {"ty": "sh", "nm": f"{name} path", "ks": static(path)},
            {"ty": "st", "nm": "Soft wet sheen", "c": static([1, 1, 1, 1]), "o": static(100), "w": static(4), "lc": 2, "lj": 2},
            {"ty": "tr", "nm": "Transform", **transform()},
        ],
        "ip": 0, "op": END, "st": 0, "bm": 0,
    }


def position_keyframes(start, end, x, y0, y1):
    mid = start + round((end - start) * 0.62)
    ym = y0 + (y1 - y0) * 0.38
    ease = {"x": [0.45], "y": [0.0]}
    ease_in = {"x": [0.55], "y": [1.0]}
    return {"a": 1, "k": [
        {"t": start, "s": [x, y0, 0], "e": [x, ym, 0], "o": ease, "i": ease_in},
        {"t": mid, "s": [x, ym, 0], "e": [x, y1, 0], "o": ease, "i": ease_in},
        {"t": end, "s": [x, y1, 0]},
    ]}


def opacity_window(start, end):
    return {"a": 1, "k": [
        {"t": max(0, start - 1), "s": [0], "e": [100], "h": 1},
        {"t": start, "s": [100], "e": [100], "h": 1},
        {"t": end - 2, "s": [100], "e": [0], "h": 1},
        {"t": end, "s": [0]},
    ]}


def drop_layer(index, name, start, end, x, y0, y1, size):
    return {
        "ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1,
        "ks": {
            "o": opacity_window(start, end), "r": static(0),
            "p": position_keyframes(start, end, x, y0, y1),
            "a": static([0, 0, 0]),
            "s": {"a": 1, "k": [
                {"t": start, "s": [72, 145, 100], "e": [100, 100, 100], "o": {"x": [0.3], "y": [0]}, "i": {"x": [0.7], "y": [1]}},
                {"t": start + 18, "s": [100, 100, 100]},
            ]},
        },
        "shapes": [
            {"ty": "el", "nm": "Drop", "p": static([0, 0]), "s": static([size, size * 1.35])},
            {"ty": "fl", "nm": "Fresh green", "c": static(FRESH), "o": static(96), "r": 1},
            {"ty": "tr", "nm": "Transform", **transform()},
        ],
        "ip": max(0, start - 1), "op": min(END, end + 1), "st": 0, "bm": 0,
    }


def puddle_layer(index, name, landing, x, y, width):
    return {
        "ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1,
        "ks": {
            "o": {"a": 1, "k": [
                {"t": landing - 1, "s": [0], "e": [64], "h": 1},
                {"t": landing, "s": [64], "e": [52], "o": {"x": [0.167], "y": [0.167]}, "i": {"x": [0.833], "y": [0.833]}},
                {"t": END, "s": [52]},
            ]},
            "r": static(0), "p": static([x, y, 0]), "a": static([0, 0, 0]),
            "s": {"a": 1, "k": [
                {"t": landing - 1, "s": [0, 0, 100], "e": [100, 100, 100], "h": 1},
                {"t": landing, "s": [100, 100, 100], "e": [118, 100, 100], "o": {"x": [0.2], "y": [0]}, "i": {"x": [0.8], "y": [1]}},
                {"t": landing + 18, "s": [118, 100, 100]},
            ]},
        },
        "shapes": [
            {"ty": "el", "nm": "Tiny puddle", "p": static([0, 0]), "s": static([width, 5])},
            {"ty": "fl", "nm": "Drying green", "c": linear_keyframes(landing, END, FRESH, DRY), "o": static(100), "r": 1},
            {"ty": "tr", "nm": "Transform", **transform()},
        ],
        "ip": landing - 1, "op": END, "st": 0, "bm": 0,
    }


def main():
    drops = [
        (120, 210, 478, 430, 782, 9),   # 4.0–7.0s
        (285, 390, 616, 442, 783, 8),   # 9.5–13.0s
        (450, 570, 503, 600, 786, 10),  # 15.0–19.0s
        (570, 660, 520, 625, 787, 7),   # 19.0–22.0s
        (900, 1020, 598, 500, 784, 8),  # 30.0–34.0s
    ]

    layers = []
    idx = 1
    for number, (start, end, x, y0, y1, size) in enumerate(drops, 1):
        layers.append(drop_layer(idx, f"Falling drop {number}", start, end, x, y0, y1, size)); idx += 1
        layers.append(puddle_layer(idx, f"Tiny puddle {number}", end, x, y1 + 3, size * 2.2)); idx += 1

    layers.append(image_layer(idx, "Dry paint colour overlay", "dry_overlay", linear_keyframes(0, END, [0], [100]))); idx += 1
    layers.append(image_layer(idx, "Original illustration", "reference", static(100)))

    lottie = {
        "v": "5.12.2", "fr": FPS, "ip": 0, "op": END, "w": 1024, "h": 1024,
        "nm": "Nima — 60 Second Paint Drying", "ddd": 0,
        "assets": [
            {"id": "reference", "w": 1564, "h": 1056, "u": "assets/", "p": "nima_paint_reference.png", "e": 0},
            {"id": "dry_overlay", "w": 1564, "h": 1056, "u": "assets/", "p": "nima_paint_dry_overlay_v2.png", "e": 0},
        ],
        "layers": layers,
        "markers": [
            {"tm": 0, "cm": "Fresh — 0 seconds", "dr": 0},
            {"tm": 450, "cm": "15 seconds", "dr": 0},
            {"tm": 900, "cm": "Half dry — 30 seconds", "dr": 0},
            {"tm": 1350, "cm": "45 seconds", "dr": 0},
            {"tm": 1799, "cm": "Dry — 60 seconds", "dr": 0},
        ],
    }
    output = ROOT / "nima_paint_drying.json"
    output.write_text(json.dumps(lottie, separators=(",", ":")), encoding="utf-8")
    print(f"Created {output.name} ({output.stat().st_size:,} bytes, {len(layers)} layers)")


if __name__ == "__main__":
    main()
