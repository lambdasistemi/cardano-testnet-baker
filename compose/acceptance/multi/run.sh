#!/usr/bin/env bash
# Multi-pool compose acceptance: brings up 3 cardano-node containers
# laid out by adapt.sh and waits for a success bar across all of them.
#
# Modes:
#   chaindb-opened    — wait until each pool logs `Opened db with` (or
#                       `Started opening Chain DB`).  Used by the
#                       antithesis-master flow: proves the per-pool
#                       layout is wired correctly and the node boots.
#   block-agreement   — wait until each pool logs an
#                       `AddedToCurrentChain` event for a non-genesis
#                       block (blockNo >= 1) AND there exists a chain
#                       tip hash that appears in all three pools' logs.
#                       Used by the antithesis-fast flow: proves the
#                       ring topology lets blocks propagate and that
#                       the network reaches agreement on a chain past
#                       genesis.
set -euo pipefail

usage() {
  printf 'usage: %s <scenario-name> <baked-output-dir> <mode>\n' "$0" >&2
  printf '       mode in {chaindb-opened, epoch-boundary}\n' >&2
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

scenario_name=$1
baked_output_dir=$2
mode=$3

case "$mode" in
  chaindb-opened|block-agreement) ;;
  *) usage; exit 2 ;;
esac

if [[ ! -d $baked_output_dir ]]; then
  printf 'baked output directory not found: %s\n' "$baked_output_dir" >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tmp_root=${ACCEPTANCE_TMP_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/ctb-multi-acceptance.XXXXXX")}
runtime_dir="$tmp_root/runtime"
project_name="ctb-multi-${scenario_name//[^[:alnum:]]/-}-$$"
log_dir=${ACCEPTANCE_LOG_DIR:-"$PWD/tmp/acceptance-logs/$project_name"}
compose_file="$script_dir/docker-compose.yaml"

case "$mode" in
  chaindb-opened)  deadline_seconds=${ACCEPTANCE_DEADLINE_SECONDS:-60} ;;
  block-agreement) deadline_seconds=${ACCEPTANCE_DEADLINE_SECONDS:-90} ;;
esac
poll_seconds=${ACCEPTANCE_POLL_SECONDS:-2}

mkdir -p "$runtime_dir" "$log_dir"
"$script_dir/adapt.sh" "$baked_output_dir" "$runtime_dir"

export ACCEPTANCE_RUNTIME_DIR=$runtime_dir
export COMPOSE_PROJECT_NAME=$project_name

cleanup() {
  docker compose -f "$compose_file" -p "$project_name" down --volumes --remove-orphans >/dev/null 2>&1 || true
  if [[ ${ACCEPTANCE_KEEP_TMP:-false} != true ]]; then
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

printf 'scenario=%s\n' "$scenario_name"
printf 'mode=%s\n' "$mode"
printf 'runtime=%s\n' "$runtime_dir"
printf 'composeProject=%s\n' "$project_name"
printf 'deadlineSeconds=%s\n' "$deadline_seconds"

docker compose -f "$compose_file" -p "$project_name" up -d --quiet-pull

pools=(p1 p2 p3)
fail_patterns='AesonException|CardanoProtocolInstantiationError|GenesisDecodeError|OtherPermissionsExist|required file not found'
chaindb_opened_pattern='Net\.Server\.Local\.Started|Started opening Chain DB|Opened db with'
# Extract the newtip hash (between quotes, before the @ separator) for
# any AddedToCurrentChain event with blockNo >= 1.  Genesis is blockNo
# 0; we want the first forged block.
block_hash_extract='AddedToCurrentChain.*"blockNo":[1-9][0-9]*.*"newtip":"([0-9a-f]+)@[0-9]+"'

declare -A reached
for p in "${pools[@]}"; do reached[$p]=0; done

check_success() {
  case "$mode" in
    chaindb-opened)
      local p
      for p in "${pools[@]}"; do
        if grep -Eq "$chaindb_opened_pattern" "$log_dir/$p.log"; then
          reached[$p]=1
        fi
      done
      local total=0 p
      for p in "${pools[@]}"; do total=$(( total + reached[$p] )); done
      (( total == ${#pools[@]} ))
      ;;
    block-agreement)
      # Per pool: collect chain-tip hashes for blockNo >= 1.  Pass when
      # the intersection across all pools is non-empty.
      local p tmp_intersection tmp_pool intersection_file=""
      for p in "${pools[@]}"; do
        tmp_pool=$(mktemp)
        grep -oE "$block_hash_extract" "$log_dir/$p.log" \
          | sed -E 's/.*"newtip":"([0-9a-f]+)@[0-9]+"/\1/' \
          | sort -u > "$tmp_pool"
        if [[ ! -s $tmp_pool ]]; then
          rm -f "$tmp_pool"
          [[ -n $intersection_file ]] && rm -f "$intersection_file"
          return 1
        fi
        if [[ -z $intersection_file ]]; then
          intersection_file=$tmp_pool
        else
          tmp_intersection=$(mktemp)
          comm -12 "$intersection_file" "$tmp_pool" > "$tmp_intersection"
          rm -f "$intersection_file" "$tmp_pool"
          intersection_file=$tmp_intersection
        fi
      done
      local nonempty=1
      if [[ -s $intersection_file ]]; then
        nonempty=0
      fi
      rm -f "$intersection_file"
      return $nonempty
      ;;
  esac
}

deadline=$((SECONDS + deadline_seconds))
while (( SECONDS < deadline )); do
  for p in "${pools[@]}"; do
    docker compose -f "$compose_file" -p "$project_name" logs --no-color "$p" \
      > "$log_dir/$p.log" 2>&1 || true

    if grep -Eq "$fail_patterns" "$log_dir/$p.log"; then
      printf 'verdict=failed\npool=%s\nlogPath=%s\n' "$p" "$log_dir/$p.log" >&2
      tail -n 60 "$log_dir/$p.log" >&2
      exit 1
    fi

    container_id=$(docker compose -f "$compose_file" -p "$project_name" ps -q "$p" || true)
    if [[ -n $container_id ]]; then
      running=$(docker inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || true)
      if [[ $running != true ]]; then
        printf 'verdict=failed\npool=%s\nreason=container-exited\nlogPath=%s\n' "$p" "$log_dir/$p.log" >&2
        tail -n 60 "$log_dir/$p.log" >&2
        exit 1
      fi
    fi
  done

  if check_success; then
    printf 'verdict=accepted\nmode=%s\nlogDir=%s\n' "$mode" "$log_dir"
    exit 0
  fi

  sleep "$poll_seconds"
done

for p in "${pools[@]}"; do
  docker compose -f "$compose_file" -p "$project_name" logs --no-color "$p" \
    > "$log_dir/$p.log" 2>&1 || true
done

printf 'verdict=failed\nreason=timeout\nmode=%s\n' "$mode" >&2
for p in "${pools[@]}"; do
  printf 'pool=%s logPath=%s\n' "$p" "$log_dir/$p.log" >&2
done
exit 1
