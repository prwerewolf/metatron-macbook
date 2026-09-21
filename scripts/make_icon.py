#!/usr/bin/env python3
import os
import math
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def create_metatron_icon():
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Standard macOS squircle dimensions: inset ~80px on 1024 canvas
    inset = 80
    corner_radius = 185
    rect = [inset, inset, size - inset, size - inset]

    # 1. Base Squircle with Deep Midnight Gradient
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base_draw = ImageDraw.Draw(base)

    # Gradient fill inside rounded rect
    for y in range(rect[1], rect[3]):
        progress = (y - rect[1]) / (rect[3] - rect[1])
        # Deep space dark indigo to obsidian purple
        r = int(18 + progress * 25)
        g = int(14 + progress * 15)
        b = int(38 + progress * 45)
        base_draw.line([(rect[0], y), (rect[2], y)], fill=(r, g, b, 255))

    # Mask to rounded rectangle
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(rect, radius=corner_radius, fill=255)

    base.putalpha(mask)

    # 2. Add subtle glass rim border
    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    border_draw.rounded_rectangle(rect, radius=corner_radius, outline=(255, 255, 255, 45), width=4)

    # Composite base onto canvas with drop shadow
    shadow_mask = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_mask)
    s_rect = [inset + 10, inset + 25, size - inset - 10, size - inset + 25]
    s_draw.rounded_rectangle(s_rect, radius=corner_radius, fill=(0, 0, 0, 110))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(radius=28))
    img.alpha_composite(shadow_mask)
    img.alpha_composite(base)
    img.alpha_composite(border)

    # 3. Center Graphic: Luminous Soundwave & Celestial Orb
    center_x = size // 2
    center_y = size // 2

    # Glowing aura
    aura = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    a_draw = ImageDraw.Draw(aura)
    a_draw.ellipse([center_x - 220, center_y - 220, center_x + 220, center_y + 220], fill=(0, 210, 255, 40))
    a_draw.ellipse([center_x - 140, center_y - 140, center_x + 140, center_y + 140], fill=(168, 85, 247, 60))
    aura = aura.filter(ImageFilter.GaussianBlur(radius=40))
    img.alpha_composite(aura)

    # Draw Soundwave bars (dynamic heights, celestial cyan-to-purple gradient)
    wave_bars = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    w_draw = ImageDraw.Draw(wave_bars)

    # 7 bars representing the voice transcription wave
    heights = [120, 220, 360, 480, 360, 220, 120]
    bar_width = 38
    spacing = 54
    total_w = len(heights) * bar_width + (len(heights) - 1) * (spacing - bar_width)
    start_x = center_x - total_w // 2

    for i, h in enumerate(heights):
        bx = start_x + i * spacing
        top = center_y - h // 2
        bottom = center_y + h // 2

        # Draw vertical capsule
        for y in range(top, bottom):
            t = (y - top) / max(1, h)
            # Cyan to violet gradient
            cr = int(34 + t * 180)
            cg = int(211 - t * 120)
            cb = int(238 + t * 17)
            w_draw.line([(bx, y), (bx + bar_width, y)], fill=(cr, cg, cb, 255))

        # Cap ends
        radius = bar_width // 2
        w_draw.ellipse([bx, top - radius, bx + bar_width, top + radius], fill=(34, 211, 238, 255))
        w_draw.ellipse([bx, bottom - radius, bx + bar_width, bottom + radius], fill=(214, 91, 255, 255))

    # Add soft glow to wave bars
    wave_glow = wave_bars.filter(ImageFilter.GaussianBlur(radius=8))
    img.alpha_composite(wave_glow)
    img.alpha_composite(wave_bars)

    # 4. Export iconset for iconutil
    iconset_dir = "Resources/AppIcon.iconset"
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, s in sizes:
        resized = img.resize((s, s), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))

    # Compile to AppIcon.icns
    icns_path = "Resources/AppIcon.icns"
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print(f"Generated {icns_path} successfully!")

if __name__ == "__main__":
    create_metatron_icon()
