#!/usr/bin/env bash

# Source this file to use the pinned user-local OSS CAD Suite in the current shell.
export OSS_CAD_SUITE_ROOT="${OSS_CAD_SUITE_ROOT:-${HOME}/.local/opt/oss-cad-suite-20260830}"
if [[ ! -x "$OSS_CAD_SUITE_ROOT/bin/yosys" ]]; then
  echo "OSS CAD Suite not found. Set OSS_CAD_SUITE_ROOT, for example:" >&2
  echo "  export OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite" >&2
  return 2 2>/dev/null || exit 2
fi
export PATH="$OSS_CAD_SUITE_ROOT/bin:$PATH"
