#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/oss_cad_suite_env.sh"

yosys_bin="${YOSYS:-$OSS_CAD_SUITE_ROOT/bin/yosys}"
build_root="$repo_root/build/synth"
flow_script="$repo_root/synth/yosys_generic.tcl"
configs=(n1_k1 n2_k2 n4_k4)

if [[ ! -x "$yosys_bin" ]]; then
    echo "Yosys executable not found: $yosys_bin" >&2
    exit 1
fi

yosys_bin="$(readlink -f "$yosys_bin")"
flow_script="$(readlink -f "$flow_script")"
mkdir -p "$build_root"
build_root="$(readlink -f "$build_root")"
expected_build_root="$(readlink -f "$repo_root/build/synth")"
if [[ "$build_root" != "$expected_build_root" ]]; then
    echo "Refusing unexpected build root: $build_root" >&2
    exit 1
fi

staging_root="$(mktemp -d "$build_root/.run.XXXXXX")"
staging_root="$(readlink -f "$staging_root")"
if [[ "$staging_root" != "$build_root"/.run.* ]]; then
    echo "Refusing unexpected staging root: $staging_root" >&2
    exit 1
fi

published=()
backed_up=()
summary_backups=()
published_summaries=()

rollback_publish() {
    local name
    set +e
    for name in "${published[@]}"; do
        if [[ -d "$build_root/$name" ]]; then
            mv "$build_root/$name" "$staging_root/$name.failed_publish"
        fi
    done
    for name in "${backed_up[@]}"; do
        if [[ -d "$staging_root/$name.previous" ]]; then
            mv "$staging_root/$name.previous" "$build_root/$name"
        fi
    done
    for name in "${published_summaries[@]}"; do
        if [[ -f "$build_root/$name" ]]; then
            mv "$build_root/$name" "$staging_root/$name.failed_publish"
        fi
    done
    for name in "${summary_backups[@]}"; do
        if [[ -f "$staging_root/$name.previous" ]]; then
            mv -f "$staging_root/$name.previous" "$build_root/$name"
        fi
    done
    if [[ -d "$staging_root" && "$staging_root" == "$build_root"/.run.* ]]; then
        rm -rf -- "$staging_root"
    fi
}

trap 'rollback_publish' ERR

run_config() {
    local name="$1"
    local formal_dir="$build_root/$name"
    export SYNTH_N="$2"
    export SYNTH_K="$3"
    export SYNTH_DATA_W=8
    export SYNTH_ACC_W=18
    export SYNTH_OUT_DIR="$staging_root/$name"

    case "$name" in
        n1_k1|n2_k2|n4_k4) ;;
        *) echo "Refusing unknown configuration: $name" >&2; return 1 ;;
    esac
    mkdir "$SYNTH_OUT_DIR"

    {
        echo "utc_run_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "git_commit=$(git -C "$repo_root" rev-parse HEAD)"
        echo "git_status_porcelain_begin"
        git -C "$repo_root" status --porcelain
        echo "git_status_porcelain_end"
        echo "yosys_executable=$yosys_bin"
        echo "yosys_version=$($yosys_bin -V)"
        echo "oss_cad_suite_root=$OSS_CAD_SUITE_ROOT"
        echo "N=$SYNTH_N"
        echo "K=$SYNTH_K"
        echo "DATA_W=$SYNTH_DATA_W"
        echo "ACC_W=$SYNTH_ACC_W"
        echo "synthesis_tcl=$flow_script"
        echo "output_directory=$formal_dir"
    } > "$SYNTH_OUT_DIR/config.txt"

    echo "[SYNTH] $name"
    (
        cd "$repo_root"
        "$yosys_bin" -c "$flow_script" -l "$SYNTH_OUT_DIR/yosys.log"
    )
}

run_config n1_k1 1 1
run_config n2_k2 2 2
run_config n4_k4 4 4

python3 "$repo_root/scripts/check_synth_structure.py" "$staging_root" \
    | tee "$staging_root/structure_summary.tsv"

# Back up only the three validated configuration directories.
for name in "${configs[@]}"; do
    formal_dir="$build_root/$name"
    if [[ -e "$formal_dir" && ! -d "$formal_dir" ]]; then
        echo "Refusing non-directory synthesis target: $formal_dir" >&2
        exit 1
    fi
    if [[ -d "$formal_dir" ]]; then
        mv "$formal_dir" "$staging_root/$name.previous"
        backed_up+=("$name")
    fi
done

for name in structure_summary.tsv structure_summary.json; do
    if [[ -e "$build_root/$name" && ! -f "$build_root/$name" ]]; then
        echo "Refusing non-file synthesis summary target: $build_root/$name" >&2
        exit 1
    fi
    if [[ -f "$build_root/$name" ]]; then
        mv "$build_root/$name" "$staging_root/$name.previous"
        summary_backups+=("$name")
    fi
done

# Publish only after every synthesis and structural check has succeeded.
for name in "${configs[@]}"; do
    mv "$staging_root/$name" "$build_root/$name"
    published+=("$name")
done
mv "$staging_root/structure_summary.tsv" "$build_root/structure_summary.tsv"
published_summaries+=(structure_summary.tsv)
mv "$staging_root/structure_summary.json" "$build_root/structure_summary.json"
published_summaries+=(structure_summary.json)

trap - ERR
if [[ "$staging_root" != "$build_root"/.run.* ]]; then
    echo "Refusing to clean unexpected staging root: $staging_root" >&2
    exit 1
fi
rm -rf -- "$staging_root"

echo "Generic synthesis completed for N/K=1/1, 2/2, and 4/4."
