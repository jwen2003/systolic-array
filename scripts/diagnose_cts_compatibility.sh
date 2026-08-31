#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${1:?immutable image reference required}"
output_dir="${2:?output directory required}"
mkdir -p "$output_dir"

{
  echo "HOST"
  uname -a
  uname -m
  lscpu
} > "$output_dir/host_cpu.txt"

set +e
docker run --rm --entrypoint bash "$image" -lc '
  source /OpenROAD-flow-scripts/env.sh >/dev/null
  kepler=/OpenROAD-flow-scripts/tools/install/kepler-formal/bin/kepler-formal
  echo CONTAINER
  uname -a
  uname -m
  lscpu
  echo "KEPLER_FORMAL_EXE=${KEPLER_FORMAL_EXE:-}"
  echo OPENROAD
  command -v openroad
  file "$(command -v openroad)"
  ldd "$(command -v openroad)"
  echo KEPLER
  file "$kepler"
  ldd "$kepler"
  set +e
  "$kepler" --help
  echo "KEPLER_HELP_EXIT=$?"
  set -e
  echo TOOLS
  openroad -version
  yosys -V
  sta -version 2>&1 || true
  echo CORE
  ulimit -c
  cat /proc/sys/kernel/core_pattern
' > "$output_dir/container_system.txt" 2>&1
probe_rc=$?
set -e
printf '%s\n' "$probe_rc" > "$output_dir/container_probe.exitcode"
exit "$probe_rc"
