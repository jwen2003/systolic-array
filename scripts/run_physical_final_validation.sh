#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
yosys_bin="/home/yttlj2003/.local/opt/oss-cad-suite-20260830/bin/yosys"
formal_dir="$repo_root/build/openroad/compatibility/final_formal"
mkdir -p "$formal_dir"

export FRONTEND_OUT_DIR="$formal_dir"
cd "$repo_root"
"$yosys_bin" -c physical/nangate45/frontend.tcl -l "$formal_dir/yosys.log"
export DERIVED_VERILOG="$formal_dir/post_proc.v"
"$yosys_bin" -c physical/nangate45/equivalence.tcl -l "$formal_dir/equivalence.log"
bash scripts/run_regression.sh
