#!/usr/bin/env python3
"""Draws the Promo Studio icon in the Remote Code family (navy background, white
glyph, mint accent): a vertical video card with a play button and a spark. Writes
the macOS AppIcon and the menu bar template images.

    python3 scripts/generate-icon.py

Requires Pillow. Output is deterministic, so the PNGs are committed.
"""
import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "PromoStudio/Resources/Assets.xcassets")
SS = 4  # supersampling factor

# Same palette as Remote Code's icon
TOP = (34, 40, 74)
BOTTOM = (10, 12, 26)
GLYPH = (240, 244, 255)
GLOW = (96, 140, 255)
SPARK = (122, 232, 196)


def gradient(size, top, bottom):
    image = Image.new("RGB", (size, size), top)
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return image


def star(draw, cx, cy, r, color):
    """Four-pointed spark: tips at r, valleys at 0.3 r."""
    points = []
    for i in range(8):
        angle = math.pi / 4 * i - math.pi / 2
        radius = r if i % 2 == 0 else r * 0.3
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    draw.polygon(points, fill=color)


def draw_glyph(draw, cx, cy, r, color, spark=None, stroke_scale=1.0, with_spark=True):
    """A 9:16 video card outline with a play triangle, and a spark at the top right."""
    stroke = r * 0.17 * stroke_scale
    w, h = r * 0.92, r * 1.52
    left, top = cx - w / 2 - r * 0.2, cy - h / 2 + r * 0.08
    draw.rounded_rectangle([left, top, left + w, top + h], r * 0.22, outline=color, width=int(stroke))
    pcx, pcy, pr = left + w / 2 + r * 0.03, top + h / 2, r * 0.2
    draw.polygon([(pcx - pr * 0.7, pcy - pr), (pcx - pr * 0.7, pcy + pr), (pcx + pr, pcy)], fill=color)
    if with_spark:
        star(draw, cx + r * 0.62, cy - r * 0.58, r * 0.36, spark or color)


def face(size):
    big = size * SS
    image = gradient(big, TOP, BOTTOM)
    # Soft screen glow behind the glyph, as on Remote Code's icon
    halo = Image.new("L", (big, big), 0)
    ImageDraw.Draw(halo).ellipse([big * 0.2, big * 0.25, big * 0.8, big * 0.85], fill=90)
    halo = halo.filter(ImageFilter.GaussianBlur(big * 0.1))
    image = Image.composite(Image.new("RGB", (big, big), GLOW), image, halo)
    draw_glyph(ImageDraw.Draw(image), big / 2, big / 2, big * 0.40, GLYPH, spark=SPARK)
    return image.resize((size, size), Image.LANCZOS)


def mac_icon(size):
    """macOS shape: rounded rectangle with margin and a soft shadow (same as Remote Code)."""
    big = size * SS
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    inset = big * 0.1
    box = [inset, inset, big - inset, big - inset]
    radius = (big - 2 * inset) * 0.225
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([box[0], box[1] + big * 0.012, box[2], box[3] + big * 0.012], radius, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(big * 0.012))
    canvas.alpha_composite(shadow)
    face_size = int(box[2] - box[0])
    front = face(face_size // SS).resize((face_size, face_size), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (face_size, face_size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, face_size - 1, face_size - 1], radius, fill=255)
    canvas.paste(front, (int(box[0]), int(box[1])), mask)
    return canvas.resize((size, size), Image.LANCZOS)


def template_glyph(points, badge=False):
    big = points * SS * 2
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    # The badge dot takes the place of the spark.
    draw_glyph(draw, big / 2, big / 2, big * 0.52, (0, 0, 0, 255), stroke_scale=1.2, with_spark=not badge)
    if badge:
        r = big * 0.17
        draw.ellipse([big - 2 * r, 0, big, 2 * r], fill=(0, 0, 0, 255))
    return image


def write_contents(path, contents):
    with open(os.path.join(path, "Contents.json"), "w") as handle:
        json.dump(contents, handle, indent=2)
        handle.write("\n")


def accent(light, dark):
    """AccentColor: the brand violet, lighter in dark mode (like Remote Code's teal accent)."""
    folder = os.path.join(CATALOG, "AccentColor.colorset")
    os.makedirs(folder, exist_ok=True)

    def entry(rgb, dark_mode):
        item = {"color": {"color-space": "srgb", "components": {
            "alpha": "1.000", "red": f"{rgb[0]:.3f}", "green": f"{rgb[1]:.3f}", "blue": f"{rgb[2]:.3f}"}}, "idiom": "universal"}
        if dark_mode:
            item = {"appearances": [{"appearance": "luminosity", "value": "dark"}], **item}
        return item

    write_contents(folder, {"colors": [entry(light, False), entry(dark, True)], "info": {"author": "xcode", "version": 1}})


def main():
    os.makedirs(CATALOG, exist_ok=True)
    write_contents(CATALOG, {"info": {"author": "xcode", "version": 1}})
    icon = os.path.join(CATALOG, "AppIcon.appiconset")
    os.makedirs(icon, exist_ok=True)
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            mac_icon(pixels).save(os.path.join(icon, name), optimize=True)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    write_contents(icon, {"images": images, "info": {"author": "xcode", "version": 1}})
    for name, badge in (("MenuBarIcon", False), ("MenuBarIconBadge", True)):
        folder = os.path.join(CATALOG, f"{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        entries = []
        for scale in (1, 2):
            glyph = template_glyph(18, badge).resize((18 * scale, 18 * scale), Image.LANCZOS)
            filename = f"{name}{'@2x' if scale == 2 else ''}.png"
            glyph.save(os.path.join(folder, filename))
            entries.append({"filename": filename, "idiom": "mac", "scale": f"{scale}x"})
        write_contents(folder, {
            "images": entries,
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "template"},
        })
    accent((0.49, 0.24, 0.80), (0.70, 0.48, 0.98))
    print("icons written to", os.path.relpath(CATALOG, ROOT))


if __name__ == "__main__":
    main()
