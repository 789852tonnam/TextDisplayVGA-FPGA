# FPGA Text Marquee

This Verilog project drives a 640×480 VGA display with an **EDIT** mode for entering text and a **SLIDE** mode for a scrolling sign. It uses the `tt_um_vga_example` top-level interface supported by VGA Playground.

[Open this project in VGA Playground](https://vga-playground.com/?repo=https://github.com/789852tonnam/TextDisplayVGA-FPGA&ref=main)

## Demo video

[Watch or download the demo recording](../recording_20261013_191440.mp4)

## Controls

| Button | Action |
| --- | --- |
| D-pad | Move the cursor by one cell in EDIT. |
| B | Read the current cell from RAM and increment it through `A → B → … → Z → A`. Blank cells start at A. |
| A | Write a space, ASCII `0x20`, to the current cell. |
| Select | Place `<` on the first press and `>` on the second. After completing a range, press again to begin a new selection. |
| Start | Enter SLIDE after selecting a valid range; press again in SLIDE to return to EDIT. |
| Reset | Return to EDIT, move the cursor to (0,0), and clear the selection state. |

Each button acts once on its rising edge; holding it does not repeat the action. SLIDE disables text editing and hides the cursor. Returning to EDIT preserves the text, cursor position, and completed selection.

## Selecting a message

1. Enter your message on one row, leaving a cell for a marker before and after the text.
2. Move the cursor to the cell before the first character and press Select to place `<`.
3. Move to the cell after the last character and press Select to place `>`.
4. Press Start to enter SLIDE.

For example, `<HELLO FPGA>` scrolls only `HELLO FPGA`; neither marker cell is part of the message.

The right marker must be on the same row and at least two columns to the right of the left marker, leaving at least one cell inside the range. A marker before, on top of, or directly adjacent to `<`, or on another row, is rejected. The left marker must also leave room for at least one message cell and the right marker.

Markers are display overlays. They do not overwrite RAM, so characters underneath them remain stored, although those endpoint cells are excluded from the scrolling message.

## Circuit operation

### EDIT and text RAM

EDIT displays an 80×30 grid with an 8×16 font. RAM stores 4096 seven-bit ASCII codes. The cell address is `{row[4:0], column[6:0]}`, so each row has a stride of 128 addresses.

B increments the value read from `memory[wr_adr]` at the cursor. There is no global alphabet counter. A–Y advance by one; Z and values outside A–Y become A.

RAM is initialized to zero, which the font ROM renders as blank. The `initial` block runs at startup; Reset does not erase stored text. An asynchronous read supplies the cursor or queue refill, while a synchronous read serves the VGA scan. Vivado synthesizes this memory as distributed RAM using LUTs.

### SLIDE and the eleven-character queue

- The font is enlarged eight times to 64×128 pixels per character.
- A 640-pixel-wide display fits ten complete characters. An eleventh character covers the portion entering at the right edge during movement.
- `slide_buffer[0:10]` stores eleven ASCII codes.
- `slide_phase_reg` counts 0–7, representing offsets of 0, 8, 16, …, 56 pixels.
- After eight movement steps, or 64 pixels, the queue shifts by one character and reads the next character from RAM.
- Reads wrap within the selected interior. Messages shorter than eleven characters repeat to fill the queue.
- Queue loading and movement updates occur during vertical blanking to avoid changing the queue while visible text is being drawn.
- The text is vertically centered at y=176 through y=303.

The default `SLIDE_STEP_FRAMES = 4` moves the text eight pixels every four frames. Adjust this parameter in `19_text_screen_gen_playground.v` to change speed, and `SLIDE_TOP` to change vertical placement.

### State machines

| FSM | States |
| --- | --- |
| Main mode | `EDIT`, `SLIDE` |
| Range selection | `SEL_NONE`: no selection; `SEL_END`: waiting for `>`; `SEL_READY`: complete range. |

Queue loading uses `slide_loading_reg`, `slide_ready_reg`, and counters separately from these two FSMs.

## Source files

| File | Purpose |
| --- | --- |
| `19_top_SwitchTextDisplay_playground.v` | Connects the gamepad, VGA timing, and text renderer; predicts pixel coordinates two clocks ahead. |
| `19_text_screen_gen_playground.v` | Implements editing, selection, mode changes, the queue, and text rendering. |
| `13_simpledualportMem.v` | Stores ASCII codes and supplies the cursor read port. |
| `19_ascii_rom_playground.v` | Provides the 8×16 ASCII font. |
| `gamepad_pmod.v` | Receives serial data, clock, and latch signals and decodes gamepad states. |
| `hsync_generator.v` | Generates 640×480 VGA timing. |
| `10_debounce.v` | Retained from the original project; the current circuit detects gamepad button edges directly and does not instantiate it. |

The gamepad uses `ui_in[4]` for latch, `[5]` for its serial clock, and `[6]` for data. The internal button vector is `{B,Y,Select,Start,Up,Down,Left,Right,A,X,L,R}`.

## Running in VGA Playground

### Load directly from GitHub

[Open TextDisplayVGA-FPGA in VGA Playground](https://vga-playground.com/?repo=https://github.com/789852tonnam/TextDisplayVGA-FPGA&ref=main)

This link loads the `main` branch using the root `info.yaml` and the source files in `src/`. Enable **Gamepad Mode** and press **Reset** before using the controls.

See [VGA Playground — URL Parameters](https://github.com/TinyTapeout/vga-playground#url-parameters) for the repository-loading format.

### Copy the combined source

1. From the repository root, run `python3 playground/build_bundle.py` after editing `src/`.
2. Open [VGA Playground with the Gamepad preset](https://vga-playground.com/?preset=gamepad).
3. Replace the editor's `project.v` tab with the complete contents of `playground/project.v`.
4. Keep the preset's `gamepad_pmod.v` and `hvsync_generator.v` tabs.
5. Enable Gamepad Mode and press Reset.

The top-level module uses the VGA Playground/Tiny Tapeout interface. Running on a physical FPGA board also requires a suitable pixel clock and board-specific pin constraints.

## Testing

Requirements: Vivado Simulator (`xvlog`, `xelab`, and `xsim`), Python 3 with Pillow, and `rg`.

From the repository root:

```bash
bash tests/run_tests.sh
```

If Vivado is not on PATH, specify its installation's bin directory:

```bash
VIVADO_BIN=/path/to/Vivado/bin bash tests/run_tests.sh
```

- `tb_marquee.v` checks controls, invalid ranges, overlays, queue loading and wrapping, movement cadence, return to EDIT, and Reset.
- `tb_marquee_render.v` captures RGB from the actual top-level pipeline at phase 0, phase 7, and after a queue shift.
- `check_marquee_pixels.py` compares all pixels in the three 640×480 frames against the font ROM and expected scrolling positions.

The script prints the temporary directory containing results and logs. It regenerates the combined playground file but does not modify the Verilog source files. Simulation previews are available in `playground/previews/`.

## Credits

The font/text-rendering design builds on *FPGA Prototyping by Verilog Examples* by Pong P. Chu and adaptations for Basys 3/VGA Playground. Source-file headers retain the corresponding credits.

The Gamepad PMOD module comes from [Pat Deegan / Psychogenic](https://github.com/psychogenic/gamepad-pmod). Its original copyright and SPDX license header is preserved.
