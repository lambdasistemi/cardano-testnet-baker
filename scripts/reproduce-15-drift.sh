#!/usr/bin/env bash
# Reproducer oracle for issue #15: bake examples/scenarios/normal.json
# twice and exit non-zero if the chain-db file set under
# chain-db/volatile/blocks-*.dat differs across the two runs.
#
# This script is the RED oracle for slice 1 (US2) and the RED-to-GREEN
# oracle for slice 2 (US1, FR-001/FR-002/FR-006). On the pre-fix baker
# SHA the diff is non-empty, exposing the producer-side drift documented
# in specs/015-synthesizer-nondeterminism/spec.md. On the post-fix
# baker SHA (after slice 2 lands) the diff is empty.
#
# See:
#   - specs/015-synthesizer-nondeterminism/tasks.md  Phase 3 (T007-T009)
#   - specs/015-synthesizer-nondeterminism/research.md  R-002
#   - specs/015-synthesizer-nondeterminism/quickstart.md  "Reproducer (slice 1)"
set -euo pipefail

usage() {
  printf 'usage: %s [-s <scenario-json>] [-o <work-dir>]\n' "$0" >&2
  printf '\n' >&2
  printf '  -s  scenario JSON to bake (default: examples/scenarios/normal.json)\n' >&2
  printf '  -o  working directory (default: tmp/repro-15)\n' >&2
}

scenario="examples/scenarios/normal.json"
work_dir="tmp/repro-15"

while getopts ":s:o:h" opt; do
  case "$opt" in
    s) scenario=$OPTARG ;;
    o) work_dir=$OPTARG ;;
    h) usage; exit 0 ;;
    \?) usage; exit 2 ;;
    :) usage; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if [[ $# -ne 0 ]]; then
  usage
  exit 2
fi

if [[ ! -f $scenario ]]; then
  printf 'scenario file not found: %s\n' "$scenario" >&2
  exit 1
fi

# Smallest-drifting slotCount surfaced from research.md R-002. While
# Phase 2 of feature 015 has not yet bisected the envelope, this prints
# the current (pre-bisect) slotCount of the supplied scenario as a
# best-effort hint, in line with quickstart.md "Reproducer (slice 1)".
slot_count="$(jq -r '.synthesis.slotCount // "unknown"' "$scenario")"
printf '# repro-15: scenario=%s slotCount=%s (smallest-drifting envelope: see research.md R-002)\n' \
  "$scenario" "$slot_count"

run_a="$work_dir/run-a/seed"
run_b="$work_dir/run-b/seed"

rm -rf "$work_dir"
mkdir -p "$work_dir"

bake() {
  local out_dir=$1
  printf 'baking %s -> %s\n' "$scenario" "$out_dir"
  nix run --quiet . -- bake \
    --scenario "$scenario" \
    --out "$out_dir"
}

bake "$run_a"
bake "$run_b"

# File set under chain-db/volatile/blocks-*.dat is the FR-001 oracle
# (issue #15 Background): blocks-N.dat is present in one bake and
# missing from the other when producer-side drift fires.
file_set() {
  local root=$1
  local rel="chain-db/volatile"
  if [[ ! -d "$root/$rel" ]]; then
    printf 'expected directory missing: %s\n' "$root/$rel" >&2
    return 1
  fi
  (
    cd "$root"
    find "$rel" -maxdepth 1 -name 'blocks-*.dat' -type f -printf '%P %s\n' \
      | LC_ALL=C sort
  )
}

manifest_a="$work_dir/run-a.manifest"
manifest_b="$work_dir/run-b.manifest"

file_set "$run_a" > "$manifest_a"
file_set "$run_b" > "$manifest_b"

printf '# manifest-a (%s lines):\n' "$(wc -l < "$manifest_a")"
cat "$manifest_a"
printf '# manifest-b (%s lines):\n' "$(wc -l < "$manifest_b")"
cat "$manifest_b"

if diff -u "$manifest_a" "$manifest_b" > "$work_dir/manifest.diff"; then
  printf 'verdict=deterministic\nfileSetDiff=empty\n'
else
  printf 'verdict=drift\n'
  printf '# file-set diff under chain-db/volatile/blocks-*.dat:\n'
  cat "$work_dir/manifest.diff"
  # Also surface byte-level diffs for any blocks-*.dat present in both
  # runs, since the issue's Background also flags per-file divergence.
  if diff -ruN \
    --include='blocks-*.dat' \
    "$run_a/chain-db/volatile" \
    "$run_b/chain-db/volatile" \
    > "$work_dir/blocks.diff" 2>/dev/null
  then
    printf '# byte-level diff: empty (drift is purely file-set-shape).\n'
  else
    printf '# byte-level diff (chain-db/volatile/blocks-*.dat) head:\n'
    head -n 40 "$work_dir/blocks.diff" || true
  fi
  exit 1
fi
