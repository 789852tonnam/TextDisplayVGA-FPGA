# FPGA Text Marquee

A Verilog VGA text editor and scrolling sign for a 640×480 display. Edit characters with a gamepad, select a message with `< >` overlays, and switch to a scrolling display.

vga-playground: https://vga-playground.com/?repo=https://github.com/789852tonnam/TextDisplayVGA-FPGA&ref=main

The link loads the `main` branch directly from GitHub. Enable **Gamepad Mode** in the playground and press **Reset** to begin.

## Demo video

demo record: [`recording_20261013_191440.mp4`](recording_20261013_191440.mp4)

## Quick start

1. Use the D-pad to move the cursor. Press **B** to cycle the current cell through A–Z, or **A** to clear it.
2. Leave a cell before and after your message. Press **Select** before the first character to place `<`, then after the last character to place `>` on the same row.
3. Press **Start** to scroll the selected message. Press it again to return to editing.

The scrolling display uses an eleven-character queue, a 64×128 font, and eight-pixel movement steps.

## Project files

- [`src/`](src/): Verilog modules and the [detailed documentation](src/README.md).
- [`info.yaml`](info.yaml): source-file configuration for direct GitHub loading.

See [src/README.md](src/README.md) for controls, state machines, and RAM and queue behavior.
