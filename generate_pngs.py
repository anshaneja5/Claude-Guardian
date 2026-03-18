#!/usr/bin/env python3
"""Generate 256x256 PNG images from 16x16 pixel art sprite data."""

import re
import struct
import zlib
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SPRITES_PATH = os.path.join(SCRIPT_DIR, "app", "ClaudeGuardian", "Sources", "sprites.swift")
ASSETS_DIR = os.path.join(SCRIPT_DIR, "assets")

SCALE = 16  # 16x16 pixels -> 256x256

# Color palettes: mascot -> {pixel_value: (r, g, b)} as 0.0-1.0 floats
PALETTES = {
    "cat": {
        1: (0.275, 0.275, 0.294),
        2: (0.098, 0.098, 0.11),
        3: (0.33, 0.33, 0.353),
        4: (1.0, 0.769, 0.737),
        5: (1.0, 0.733, 0.682),
        6: (1.0, 0.667, 0.247),
        7: (0.431, 0.337, 0.235),
        8: (1.0, 1.0, 1.0),
        9: (0.376, 0.376, 0.392),
    },
    "claude": {
        1: (0.93, 0.5, 0.35),
        2: (0.2, 0.15, 0.13),
        3: (1.0, 0.97, 0.95),
        4: (1.0, 0.65, 0.6),
        5: (0.12, 0.1, 0.1),
        6: (0.3, 0.85, 0.4),
        7: (0.75, 0.38, 0.25),
        8: (1.0, 0.6, 0.45),
    },
    "owl": {
        1: (0.6, 0.4, 0.22),
        2: (0.1, 0.08, 0.05),
        3: (0.95, 0.93, 0.88),
        4: (0.82, 0.7, 0.48),
        5: (0.95, 0.72, 0.15),
        6: (0.08, 0.06, 0.05),
        7: (0.75, 0.6, 0.2),
        8: (0.4, 0.27, 0.15),
    },
    "skull": {
        1: (0.85, 0.82, 0.75),
        2: (0.08, 0.08, 0.08),
        3: (0.95, 0.93, 0.88),
        4: (0.7, 0.67, 0.6),
        5: (0.8, 0.12, 0.1),
        6: (0.2, 0.9, 0.35),
        7: (0.92, 0.9, 0.85),
        8: (0.3, 0.28, 0.25),
    },
    "dog": {
        1: (0.72, 0.52, 0.3),
        2: (0.1, 0.08, 0.06),
        3: (0.95, 0.92, 0.88),
        4: (1.0, 0.5, 0.55),
        5: (0.1, 0.08, 0.06),
        6: (0.12, 0.1, 0.1),
        7: (0.5, 0.35, 0.2),
        8: (0.9, 0.82, 0.68),
    },
    "dragon": {
        1: (0.25, 0.7, 0.4),
        2: (0.08, 0.15, 0.08),
        3: (0.92, 0.95, 0.9),
        4: (0.95, 0.88, 0.4),
        5: (0.85, 0.15, 0.12),
        6: (1.0, 0.55, 0.1),
        7: (0.35, 0.55, 0.35),
        8: (0.18, 0.5, 0.28),
    },
}

# Map struct names to mascot keys
STRUCT_TO_KEY = {
    "CatSprites": "cat",
    "OwlSprites": "owl",
    "SkullSprites": "skull",
    "DogSprites": "dog",
    "DragonSprites": "dragon",
    "ClaudeSprites": "claude",
}


def parse_idle1_sprites(swift_src):
    """Parse idle1 sprite arrays from Swift source."""
    sprites = {}
    # Match each struct's idle1 array
    for struct_name, key in STRUCT_TO_KEY.items():
        # Find the idle1 definition for this struct
        pattern = rf'struct\s+{struct_name}\s*\{{.*?static\s+let\s+idle1:\s*\[\[Int\]\]\s*=\s*\[(.*?)\](?:\s*//[^\n]*)?\s*\n\s*\]'
        match = re.search(pattern, swift_src, re.DOTALL)
        if not match:
            # Try simpler approach: find "static let idle1" after the struct declaration
            struct_start = swift_src.find(f"struct {struct_name}")
            if struct_start == -1:
                print(f"WARNING: Could not find struct {struct_name}")
                continue
            idle1_start = swift_src.find("static let idle1", struct_start)
            if idle1_start == -1:
                print(f"WARNING: Could not find idle1 in {struct_name}")
                continue
            # Find the opening bracket of the outer array
            outer_start = swift_src.find("= [", idle1_start)
            if outer_start == -1:
                continue
            outer_start += 2  # point to '['

            # Find matching closing bracket - count nested brackets
            depth = 0
            i = outer_start
            while i < len(swift_src):
                if swift_src[i] == '[':
                    depth += 1
                elif swift_src[i] == ']':
                    depth -= 1
                    if depth == 0:
                        break
                i += 1

            array_text = swift_src[outer_start:i+1]
        else:
            array_text = "[" + match.group(1) + "]"

        # Parse rows: find all [...] inner arrays
        rows = []
        for row_match in re.finditer(r'\[([^\[\]]+)\]', array_text):
            row_text = row_match.group(1)
            # Remove comments
            row_text = re.sub(r'//.*', '', row_text)
            values = [int(x.strip()) for x in row_text.split(',') if x.strip()]
            if len(values) == 16:
                rows.append(values)

        if len(rows) == 16:
            sprites[key] = rows
            print(f"Parsed {struct_name} idle1: {len(rows)}x{len(rows[0])}")
        else:
            print(f"WARNING: {struct_name} idle1 has {len(rows)} rows (expected 16)")

    return sprites


def write_png(filename, rgba_data, width, height):
    """Write RGBA image data as PNG using pure Python."""
    def make_chunk(chunk_type, data):
        chunk = chunk_type + data
        crc = struct.pack('>I', zlib.crc32(chunk) & 0xffffffff)
        return struct.pack('>I', len(data)) + chunk + crc

    # PNG signature
    sig = b'\x89PNG\r\n\x1a\n'

    # IHDR
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    ihdr = make_chunk(b'IHDR', ihdr_data)

    # IDAT - build raw image data with filter bytes
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: None
        offset = y * width * 4
        raw.extend(rgba_data[offset:offset + width * 4])

    compressed = zlib.compress(bytes(raw), 9)
    idat = make_chunk(b'IDAT', compressed)

    # IEND
    iend = make_chunk(b'IEND', b'')

    with open(filename, 'wb') as f:
        f.write(sig + ihdr + idat + iend)


def render_sprite(sprite, palette, scale=SCALE):
    """Render a 16x16 sprite to a 256x256 RGBA byte array."""
    size = 16 * scale
    data = bytearray(size * size * 4)

    for row in range(16):
        for col in range(16):
            val = sprite[row][col]
            if val == 0:
                r, g, b, a = 0, 0, 0, 0
            else:
                fr, fg, fb = palette.get(val, (1.0, 0.0, 1.0))  # magenta fallback
                r = int(fr * 255 + 0.5)
                g = int(fg * 255 + 0.5)
                b = int(fb * 255 + 0.5)
                a = 255

            # Fill the scaled block
            for dy in range(scale):
                for dx in range(scale):
                    px = col * scale + dx
                    py = row * scale + dy
                    offset = (py * size + px) * 4
                    data[offset] = r
                    data[offset + 1] = g
                    data[offset + 2] = b
                    data[offset + 3] = a

    return bytes(data), size


def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)

    with open(SPRITES_PATH, 'r') as f:
        swift_src = f.read()

    sprites = parse_idle1_sprites(swift_src)

    for key in ["claude", "cat", "owl", "skull", "dog", "dragon"]:
        if key not in sprites:
            print(f"Skipping {key}: no sprite data")
            continue

        palette = PALETTES[key]
        rgba_data, size = render_sprite(sprites[key], palette)

        output_path = os.path.join(ASSETS_DIR, f"{key}.png")
        write_png(output_path, rgba_data, size, size)
        print(f"Saved {output_path} ({size}x{size})")


if __name__ == "__main__":
    main()
