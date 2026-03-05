#!/usr/bin/env python3
"""Generate FreeDisplay app icon (1024x1024)."""

import math
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
CORNER_RADIUS = int(SIZE * 0.18)  # ~18% corner radius

def make_rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask

def draw_gradient(draw, size, color1, color2):
    """Blue-to-purple diagonal gradient."""
    r1, g1, b1 = color1
    r2, g2, b2 = color2
    for y in range(size):
        t = y / (size - 1)
        r = int(r1 + (r2 - r1) * t)
        g = int(g1 + (g2 - g1) * t)
        b = int(b1 + (b2 - b1) * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Draw gradient background
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    bg_draw = ImageDraw.Draw(bg)
    draw_gradient(bg_draw, SIZE, (74, 144, 217), (123, 104, 238))  # #4A90D9 → #7B68EE

    # Apply rounded rectangle mask
    mask = make_rounded_rect_mask(SIZE, CORNER_RADIUS)
    img.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(img)

    # Monitor body dimensions
    cx, cy = SIZE // 2, SIZE // 2
    mon_w = int(SIZE * 0.58)
    mon_h = int(SIZE * 0.40)
    mon_x = cx - mon_w // 2
    mon_y = cy - mon_h // 2 - int(SIZE * 0.03)
    mon_radius = int(SIZE * 0.03)

    # Shadow behind monitor
    shadow_offset = int(SIZE * 0.015)
    shadow_color = (0, 0, 0, 60)
    shadow_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_img)
    shadow_draw.rounded_rectangle(
        [mon_x + shadow_offset, mon_y + shadow_offset,
         mon_x + mon_w + shadow_offset, mon_y + mon_h + shadow_offset],
        radius=mon_radius, fill=shadow_color
    )
    img = Image.alpha_composite(img, shadow_img)
    draw = ImageDraw.Draw(img)

    # Monitor bezel (white with slight transparency)
    bezel_color = (255, 255, 255, 220)
    draw.rounded_rectangle(
        [mon_x, mon_y, mon_x + mon_w, mon_y + mon_h],
        radius=mon_radius, fill=bezel_color
    )

    # Screen area inside bezel
    bezel_thick = int(SIZE * 0.025)
    scr_x = mon_x + bezel_thick
    scr_y = mon_y + bezel_thick
    scr_w = mon_w - bezel_thick * 2
    scr_h = mon_h - bezel_thick * 2 - int(SIZE * 0.015)  # bottom chin
    scr_radius = int(SIZE * 0.01)

    screen_color = (30, 40, 80, 255)
    draw.rounded_rectangle(
        [scr_x, scr_y, scr_x + scr_w, scr_y + scr_h],
        radius=scr_radius, fill=screen_color
    )

    # Monitor stand - neck
    neck_w = int(SIZE * 0.06)
    neck_h = int(SIZE * 0.10)
    neck_x = cx - neck_w // 2
    neck_y = mon_y + mon_h
    draw.rectangle(
        [neck_x, neck_y, neck_x + neck_w, neck_y + neck_h],
        fill=(255, 255, 255, 200)
    )

    # Monitor stand - base
    base_w = int(SIZE * 0.24)
    base_h = int(SIZE * 0.03)
    base_x = cx - base_w // 2
    base_y = neck_y + neck_h
    base_radius = int(SIZE * 0.01)
    draw.rounded_rectangle(
        [base_x, base_y, base_x + base_w, base_y + base_h],
        radius=base_radius, fill=(255, 255, 255, 200)
    )

    # Draw "F" letter on screen
    letter_cx = scr_x + scr_w // 2
    letter_cy = scr_y + scr_h // 2

    font_size = int(scr_h * 0.72)
    letter_color = (255, 255, 255, 255)

    # Draw F using rectangles (bold, clean)
    stroke = int(font_size * 0.18)
    f_h = int(font_size * 0.85)
    f_w = int(font_size * 0.58)

    fx = letter_cx - f_w // 2
    fy = letter_cy - f_h // 2

    # Vertical stroke
    draw.rectangle([fx, fy, fx + stroke, fy + f_h], fill=letter_color)

    # Top horizontal bar
    draw.rectangle([fx, fy, fx + f_w, fy + stroke], fill=letter_color)

    # Middle horizontal bar (slightly shorter)
    mid_w = int(f_w * 0.80)
    mid_y = fy + int(f_h * 0.48)
    draw.rectangle([fx, mid_y, fx + mid_w, mid_y + stroke], fill=letter_color)

    # Add subtle screen reflection
    refl_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    refl_draw = ImageDraw.Draw(refl_img)
    refl_points = [
        (scr_x + int(scr_w * 0.05), scr_y + int(scr_h * 0.05)),
        (scr_x + int(scr_w * 0.50), scr_y + int(scr_h * 0.05)),
        (scr_x + int(scr_w * 0.35), scr_y + int(scr_h * 0.40)),
        (scr_x + int(scr_w * 0.05), scr_y + int(scr_h * 0.30)),
    ]
    refl_draw.polygon(refl_points, fill=(255, 255, 255, 18))
    img = Image.alpha_composite(img, refl_img)

    out_path = "/Users/jm/Desktop/FreeDisplay/scripts/icon_1024.png"
    img.save(out_path, "PNG")
    print(f"Saved: {out_path}")

if __name__ == "__main__":
    main()
