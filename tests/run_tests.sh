#!/usr/bin/env bash
set -euo pipefail

task_root=$(cd "$(dirname "$0")/.." && pwd)
task_build=$(mktemp -d "${TMPDIR:-/tmp}/text-display-tests.XXXXXX")
task_vivado_bin=${VIVADO_BIN:-}
if [[ -z "$task_vivado_bin" ]]; then
    task_xvlog=$(command -v xvlog || true)
    if [[ -n "$task_xvlog" ]]; then
        task_vivado_bin=$(dirname "$task_xvlog")
    else
        task_vivado_bin=/home/tonumi/VivadoLib/2025.2/Vivado/bin
    fi
fi

python3 "$task_root/playground/build_bundle.py"
cd "$task_build"
"$task_vivado_bin/xvlog" \
    "$task_root/playground/project.v" \
    "$task_root/src/gamepad_pmod.v" \
    "$task_root/src/hsync_generator.v" \
    "$task_root/tests/tb_marquee.v" "$task_root/tests/tb_marquee_render.v"
"$task_vivado_bin/xelab" tb_marquee -s marquee_sim -timescale 1ns/1ps
"$task_vivado_bin/xsim" marquee_sim -runall | tee unit.log
rg -q '^PASS: edit,' unit.log
"$task_vivado_bin/xelab" tb_marquee_render -s marquee_render_sim -timescale 1ns/1ps
"$task_vivado_bin/xsim" marquee_render_sim -runall | tee render.log
rg -q '^PASS: full top-level RGB' render.log
python3 "$task_root/tests/check_marquee_pixels.py" "$task_build" "$task_build/previews"
echo "Test outputs: $task_build"
