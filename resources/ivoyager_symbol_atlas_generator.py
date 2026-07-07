#!/usr/bin/env python3
# ivoyager_symbol_atlas_generator.py
# This file is part of I, Voyager (https://ivoyager.dev)
# Copyright 2019-2026 Charlie Whitfield; Apache License, Version 2.0
# *****************************************************************************
"""Generate ivoyager_symbol_atlas.png for I, Voyager position symbols.

A 3-column x 4-row grid of 12 white-on-transparent shapes, in the default
order:

    CIRCLE,               CIRCLE_PLUS,          CLOSED_CIRCLE,
    SQUARE,               SQUARE_X,             CLOSED_SQUARE,
    UP_TRIANGLE,          CLOSED_UP_TRIANGLE,   DOWN_TRIANGLE,
    CLOSED_DOWN_TRIANGLE, X,                    PLUS

The cell index maps to atlas cell col = i % 3, row = i // 3 (row-major, top-left
origin) -- the same row-major mapping the shader (shaders/_symbol.gdshaderinc) and
IVAssetPreloader apply, driven by IVCoreSettings.symbol_atlas_columns/rows. Shapes
are white (RGB) with coverage in alpha, so consumers tint via modulate/ALBEDO and
read alpha for the shape mask.

Regenerable: tune the ratios below and re-run `python ivoyager_symbol_atlas_generator.py`.
"""

import os
from PIL import Image, ImageDraw, ImageChops

COLS, ROWS = 3, 4
CELL = 256          # final px per cell
SS = 4              # supersample factor (drawn big, then downsampled for AA)
D = CELL * SS       # drawn px per cell

PAD = 0.17          # shape inset from cell edge (fraction of drawn cell)
STROKE = 0.075      # open-shape stroke width (fraction of drawn cell)

WHITE = (255, 255, 255, 255)

ORDER = [
    "CIRCLE", "CIRCLE_PLUS", "CLOSED_CIRCLE",
    "SQUARE", "SQUARE_X", "CLOSED_SQUARE",
    "UP_TRIANGLE", "CLOSED_UP_TRIANGLE", "DOWN_TRIANGLE",
    "CLOSED_DOWN_TRIANGLE", "X", "PLUS",
]


def draw_symbol(img, name, ox, oy):
    d = ImageDraw.Draw(img)
    pad = PAD * D
    w = max(2, round(STROKE * D))
    x0, y0 = ox + pad, oy + pad
    x1, y1 = ox + D - pad, oy + D - pad
    cx, cy = ox + D / 2.0, oy + D / 2.0

    def circle(fill):
        if fill:
            d.ellipse([x0, y0, x1, y1], fill=WHITE)
        else:
            d.ellipse([x0, y0, x1, y1], outline=WHITE, width=w)

    def square(fill):
        if fill:
            d.rectangle([x0, y0, x1, y1], fill=WHITE)
        else:
            d.rectangle([x0, y0, x1, y1], outline=WHITE, width=w)

    def triangle(up, fill):
        pts = [(cx, y0), (x0, y1), (x1, y1)] if up else [(cx, y1), (x0, y0), (x1, y0)]
        if fill:
            d.polygon(pts, fill=WHITE)
        else:
            d.polygon(pts, outline=WHITE, width=w)

    def plus_segments():
        return [[(x0, cy), (x1, cy)], [(cx, y0), (cx, y1)]]

    def cross_segments():
        return [[(x0, y0), (x1, y1)], [(x0, y1), (x1, y0)]]

    def draw_segments(target, segments):
        for a, b in segments:
            target.line([a, b], fill=WHITE, width=w)

    def overlay_clipped(segments, shape):
        # A plus/x drawn over an open shape must let the shape define the outer
        # perimeter: a wide stroke's half-width would otherwise spill past the
        # outline (past the square's corners, past the circle's cardinal points).
        # Clip the strokes to the shape's silhouette so they reach it but no more.
        layer = Image.new("RGBA", (D, D), (0, 0, 0, 0))
        local = [[(a[0] - ox, a[1] - oy), (b[0] - ox, b[1] - oy)] for a, b in segments]
        draw_segments(ImageDraw.Draw(layer), local)
        mask = Image.new("L", (D, D), 0)
        box = [pad, pad, D - pad, D - pad]
        if shape == "circle":
            ImageDraw.Draw(mask).ellipse(box, fill=255)
        else:
            ImageDraw.Draw(mask).rectangle(box, fill=255)
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        img.alpha_composite(layer, (ox, oy))

    if name == "CIRCLE":
        circle(False)
    elif name == "CIRCLE_PLUS":
        circle(False); overlay_clipped(plus_segments(), "circle")
    elif name == "CLOSED_CIRCLE":
        circle(True)
    elif name == "SQUARE":
        square(False)
    elif name == "SQUARE_X":
        square(False); overlay_clipped(cross_segments(), "square")
    elif name == "CLOSED_SQUARE":
        square(True)
    elif name == "UP_TRIANGLE":
        triangle(True, False)
    elif name == "CLOSED_UP_TRIANGLE":
        triangle(True, True)
    elif name == "DOWN_TRIANGLE":
        triangle(False, False)
    elif name == "CLOSED_DOWN_TRIANGLE":
        triangle(False, True)
    elif name == "X":
        draw_segments(d, cross_segments())
    elif name == "PLUS":
        draw_segments(d, plus_segments())
    else:
        raise ValueError(name)


def main():
    img = Image.new("RGBA", (COLS * D, ROWS * D), (0, 0, 0, 0))
    for i, name in enumerate(ORDER):
        col, row = i % COLS, i // COLS
        draw_symbol(img, name, col * D, row * D)
    img = img.resize((COLS * CELL, ROWS * CELL), Image.LANCZOS)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ivoyager_symbol_atlas.png")
    img.save(out)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
