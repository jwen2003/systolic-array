#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -d "$repo_root/.git" && -f "$repo_root/physical/nangate45/clock_sweep.tsv" ]] || exit 2
orfs_root="${ORFS_ROOT:-/mnt/c/Projects/OpenROAD-flow-scripts}"
orfs_root="$(readlink -f "$orfs_root")"
image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
expected_orfs="6101364b2d7909dd797e1e3e7f80695401cfa4e4"
source "$repo_root/scripts/oss_cad_suite_env.sh"
yosys_bin="${YOSYS:-$OSS_CAD_SUITE_ROOT/bin/yosys}"
config_table="$repo_root/physical/nangate45/clock_sweep.tsv"
build_root="$repo_root/build/openroad/clock_sweep"

[[ "$(git -C "$orfs_root" -c safe.directory="$orfs_root" rev-parse HEAD)" == "$expected_orfs" ]] || { echo "ORFS commit mismatch" >&2; exit 2; }
[[ -x "$yosys_bin" ]] || { echo "Yosys not executable: $yosys_bin" >&2; exit 2; }
docker image inspect "$image" >/dev/null
image_id="$(docker image inspect --format '{{.Id}}' "$image")"
tool_versions="$(docker run --rm "$image" bash -lc 'source /OpenROAD-flow-scripts/env.sh >/dev/null; printf "openroad=%s\n" "$(openroad -version)"; printf "yosys=%s\n" "$(yosys -V)"; printf "opensta=%s\n" "$(sta -version 2>&1 | head -n1)"')"
openroad_version="$(sed -n 's/^openroad=//p' <<<"$tool_versions")"
yosys_version="$(sed -n 's/^yosys=//p' <<<"$tool_versions")"
opensta_version="$(sed -n 's/^opensta=//p' <<<"$tool_versions")"
mkdir -p "$build_root"
build_root="$(readlink -f "$build_root")"

publish_failure() {
  local stage="$1" name="$2"
  local stamp failed
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  failed="$build_root/${name}.failed.${stamp}"
  [[ "$stage" == "$build_root"/.run.* && "$failed" == "$build_root"/* ]] || exit 2
  mv "$stage" "$failed"
  echo "Preserved failed run: $failed" >&2
}

run_one() {
  local name="$1" period="$2" frequency="$3" n="$4" k="$5" data_w="$6" acc_w="$7"
  [[ "$name" =~ ^clk_[0-9]{4}ps$ && "$period" =~ ^[0-9]+\.[0-9]{3}$ && "$frequency" =~ ^[0-9]+\.[0-9]{3}$ ]] || return 2
  [[ "$n" == 2 && "$k" == 2 && "$data_w" == 8 && "$acc_w" == 18 ]] || return 2
  local final="$build_root/$name"
  if [[ -d "$final" ]]; then
    python3 "$repo_root/scripts/check_clock_sweep_result.py" "$final" >/dev/null
    echo "Keeping validated existing result: $name"
    return 0
  fi
  [[ ! -e "$final" ]] || { echo "Refusing non-directory result: $final" >&2; return 2; }
  local stage
  stage="$(mktemp -d "$build_root/.run.${name}.XXXXXX")"
  stage="$(readlink -f "$stage")"
  [[ "$stage" == "$build_root"/.run."$name".* ]] || return 2
  mkdir -p "$stage/frontend" "$stage/work"

  export FRONTEND_OUT_DIR="$stage/frontend"
  (cd "$repo_root" && "$yosys_bin" -c physical/nangate45/frontend.tcl -l "$stage/frontend/yosys.log")
  export DERIVED_VERILOG="$stage/frontend/post_proc.v"
  (cd "$repo_root" && "$yosys_bin" -c physical/nangate45/equivalence.tcl -l "$stage/frontend/equivalence.log")

  sed "s/-period 2\.500 /-period $period /" "$repo_root/physical/nangate45/constraint.sdc" > "$stage/constraint.sdc"
  [[ "$(grep -c -- "-period $period " "$stage/constraint.sdc")" == 1 ]] || return 2
  sed "s/-period $period /-period 2.500 /" "$stage/constraint.sdc" | cmp -s - "$repo_root/physical/nangate45/constraint.sdc" || return 2
  {
    echo 'include /work/physical/nangate45/config.mk'
    echo "override export CLOCK_PERIOD = $period"
    echo "override export SDC_FILE = /work/${stage#"$repo_root"/}/constraint.sdc"
  } > "$stage/config.mk"

  local dirty status_flat constraint_hash
  dirty=false
  [[ -n "$(git -C "$repo_root" status --porcelain)" ]] && dirty=true
  status_flat="$(git -C "$repo_root" status --porcelain | base64 -w0)"
  constraint_hash="$(sha256sum "$stage/constraint.sdc" | awk '{print $1}')"
  {
    echo "name=$name"; echo "clock_period_ns=$period"; echo "nominal_frequency_mhz=$frequency"
    echo "N=$n"; echo "K=$k"; echo "DATA_W=$data_w"; echo "ACC_W=$acc_w"
    echo "git_commit=$(git -C "$repo_root" rev-parse HEAD)"; echo "git_dirty=$dirty"; echo "git_status_porcelain=$status_flat"
    echo "orfs_commit=$expected_orfs"; echo "image=$image"; echo "image_id=$image_id"
    echo "openroad_version=$openroad_version"; echo "yosys_version=$yosys_version"; echo "opensta_version=$opensta_version"
    echo "constraint_sha256=$constraint_hash"; echo "lec_check=0"; echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$stage/manifest.txt"

  set +e
  docker run --rm \
    -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" -v "$repo_root:/work" \
    -e FLOW_HOME=/OpenROAD-flow-scripts/flow -e WORK_HOME="/work/${stage#"$repo_root"/}/work" \
    -e SYSTOLIC_DERIVED_V="/work/${stage#"$repo_root"/}/frontend/post_proc.v" \
    -e OPENROAD_NUM_THREADS=16 -e OMP_NUM_THREADS=16 \
    "$image" bash -lc "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/${stage#"$repo_root"/}/config.mk all drc" \
    > "$stage/docker.log" 2>&1
  local flow_rc=$?
  set -e
  printf '%s\n' "$flow_rc" > "$stage/docker.exitcode"
  if [[ "$flow_rc" -ne 0 ]]; then
    local failed_status="infrastructure_or_tool_failure"
    [[ -s "$stage/work/results/nangate45/systolic_array_n2_k2/base/6_final.odb" ]] || failed_status="flow_failed_before_final_route"
    printf '{"flow_status":"%s","docker_exitcode":%d}\n' "$failed_status" "$flow_rc" > "$stage/failure_status.json"
    publish_failure "$stage" "$name"
    return 1
  fi
  if ! "$repo_root/scripts/run_openroad_final_audit.sh" "$stage"; then publish_failure "$stage" "$name"; return 1; fi
  if ! python3 "$repo_root/scripts/check_clock_sweep_result.py" "$stage" > "$stage/checker.log"; then publish_failure "$stage" "$name"; return 1; fi
  mv "$stage" "$final"
  echo "Published $name"
}

count=0
while IFS=$'\t' read -r name period frequency n k data_w acc_w; do
  [[ "$name" == name ]] && continue
  [[ -z "$name" ]] && continue
  run_one "$name" "$period" "$frequency" "$n" "$k" "$data_w" "$acc_w"
  count=$((count + 1))
done < "$config_table"
[[ "$count" == 5 ]] || { echo "Expected five configurations" >&2; exit 2; }
