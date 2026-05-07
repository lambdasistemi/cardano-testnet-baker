#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s <runtime-artifact-dir>\n' "$0" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

runtime_dir=$1
shelley_genesis="$runtime_dir/genesis/shelley-genesis.json"
byron_genesis="$runtime_dir/genesis/byron-genesis.json"

for file in "$shelley_genesis" "$byron_genesis"; do
  if [[ ! -f $file ]]; then
    printf 'missing genesis file: %s\n' "$file" >&2
    exit 1
  fi
done

system_start=${ACCEPTANCE_SYSTEM_START:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
start_time=${ACCEPTANCE_START_TIME:-$(date -u +%s)}

tmp=$(mktemp)
jq --arg systemStart "$system_start" \
  '. + {systemStart: $systemStart}' \
  "$shelley_genesis" > "$tmp"
mv "$tmp" "$shelley_genesis"

tmp=$(mktemp)
jq --argjson startTime "$start_time" \
  '.startTime = $startTime' \
  "$byron_genesis" > "$tmp"
mv "$tmp" "$byron_genesis"
