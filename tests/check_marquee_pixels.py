"""Check top-level RGB captures against the font and the marquee contract.

Usage: python3 check_marquee_pixels.py CAPTURE_DIRECTORY OUTPUT_DIRECTORY
"""
from pathlib import Path
import re
import sys
from PIL import Image

capture_dir = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
output_dir.mkdir(parents=True, exist_ok=True)
font_path = Path(__file__).resolve().parents[1] / "src/19_ascii_rom_playground.v"
glyphs = {
    int(char, 16): bytes.fromhex(rows)
    for char, rows in re.findall(r"7'h([0-9a-f]{2}): glyph = 128'h([0-9a-f]{32});", font_path.read_text())
}
message = b"HELLO FPGA123"
for name, movement in [("phase0", 0), ("phase7", 56), ("shifted", 64)]:
    raw = [int(pixel, 16) for pixel in (capture_dir / f"marquee_{name}.hex").read_text().split()]
    assert len(raw) == 640 * 480, f"Incomplete {name} capture"
    errors = []
    for y in range(480):
        for x in range(640):
            expected = 0
            if 176 <= y < 304:
                source_x = x + movement
                char = message[(source_x // 64) % len(message)]
                font_row = (y - 176) // 8
                font_col = (source_x % 64) // 8
                if glyphs[char][font_row] & (0x80 >> font_col):
                    expected = 0x3F
            actual = raw[y * 640 + x]
            if actual != expected and len(errors) < 10:
                errors.append((x, y, expected, actual))
    assert not errors, f"{name} pixel mismatches (x,y,expected,actual): {errors}"
    pixels = [(((v >> 4) & 3) * 85, ((v >> 2) & 3) * 85, (v & 3) * 85) for v in raw]
    preview = Image.new("RGB", (640, 480))
    preview.putdata(pixels)
    preview.save(output_dir / f"slide_{name}.png")
    print(f"PASS: {name}: all 307200 top-level RGB pixels match the 64x128 font and offset {movement}")
