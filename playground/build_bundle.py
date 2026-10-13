"""Build the single-file VGA Playground version from the Vivado sources."""
from pathlib import Path

root = Path(__file__).resolve().parent
source = root.parent / "src"
files = [
    "19_top_SwitchTextDisplay_playground.v",
    "19_text_screen_gen_playground.v",
    "13_simpledualportMem.v",
    "10_debounce.v",
    "19_ascii_rom_playground.v",
]
parts = [
    "// Paste into project.v at https://vga-playground.com/?preset=gamepad\n"
    "// Keep the preset gamepad_pmod.v and hvsync_generator.v tabs.\n"
    "// EDIT: D-pad moves, B increments, A erases, Select places < then >.\n"
    "// Start toggles EDIT/SLIDE after selecting a nonempty single-row range.\n"
    "// SLIDE: eleven ASCII codes, 64x128 font, eight-pixel movement steps.\n"
]
for index, name in enumerate(files):
    parts.append(f"// ===== Source: {name} =====\n" + (source / name).read_text().rstrip() + "\n")
    if index == 0:
        parts.append("`default_nettype wire\n")
parts.append("`default_nettype wire\n")
(root / "project.v").write_text("\n".join(parts))
print(root / "project.v")
