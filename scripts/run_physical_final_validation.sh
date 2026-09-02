#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
source "$repo_root/scripts/oss_cad_suite_env.sh"
yosys_bin="${YOSYS:-$OSS_CAD_SUITE_ROOT/bin/yosys}"
[[ -x "$yosys_bin" ]] || { echo "Yosys not executable: $yosys_bin" >&2; exit 2; }
formal_dir="$repo_root/build/openroad/compatibility/final_formal"
mkdir -p "$formal_dir"

export FRONTEND_OUT_DIR="$formal_dir"
cd "$repo_root"
"$yosys_bin" -c physical/nangate45/frontend.tcl -l "$formal_dir/yosys.log"
export DERIVED_VERILOG="$formal_dir/post_proc.v"
"$yosys_bin" -c physical/nangate45/equivalence.tcl -l "$formal_dir/equivalence.log"
bash scripts/run_regression.sh
