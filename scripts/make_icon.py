#!/usr/bin/env python3
import os
import subprocess
from PIL import Image

def build_app_icon():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    master_path = os.path.join(base_dir, "Resources", "AppIcon_master.png")
    iconset_dir = os.path.join(base_dir, "Resources", "AppIcon.iconset")
    icns_path = os.path.join(base_dir, "Resources", "AppIcon.icns")

    if not os.path.exists(master_path):
        print(f"Master icon not found at {master_path}")
        return

    img = Image.open(master_path).convert("RGBA")
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

    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print(f"Successfully generated {icns_path}")

if __name__ == "__main__":
    build_app_icon()
