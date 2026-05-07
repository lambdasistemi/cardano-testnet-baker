#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s <scenario-name> <baked-output-dir>\n' "$0" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

scenario_name=$1
baked_output_dir=$2

if [[ ! -d $baked_output_dir ]]; then
  printf 'baked output directory not found: %s\n' "$baked_output_dir" >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tmp_root=${ACCEPTANCE_TMP_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/cardano-testnet-baker-acceptance.XXXXXX")}
runtime_dir="$tmp_root/runtime"
project_name="ctb-${scenario_name//[^[:alnum:]]/-}-$$"
log_dir=${ACCEPTANCE_LOG_DIR:-"$PWD/tmp/acceptance-logs/$project_name"}
compose_file="$script_dir/docker-compose.yaml"
node_image=${CARDANO_NODE_IMAGE:-ghcr.io/intersectmbo/cardano-node@sha256:3275d357053d21f3220f74b0854fd584e1fe322dfa1bbb78effd760c3191d14c}
deadline_seconds=${ACCEPTANCE_DEADLINE_SECONDS:-30}
poll_seconds=${ACCEPTANCE_POLL_SECONDS:-1}

mkdir -p "$runtime_dir" "$log_dir"
cp -R "$baked_output_dir/." "$runtime_dir/"
cp "$script_dir/topology/topology.json" "$runtime_dir/topology.json"
"$script_dir/patch-system-start.sh" "$runtime_dir"

export ACCEPTANCE_RUNTIME_DIR=$runtime_dir
export CARDANO_NODE_IMAGE=$node_image
export COMPOSE_PROJECT_NAME=$project_name

cleanup() {
  docker compose -f "$compose_file" down --volumes --remove-orphans >/dev/null 2>&1 || true
  if [[ ${ACCEPTANCE_KEEP_TMP:-false} != true ]]; then
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

printf 'scenario=%s\n' "$scenario_name"
printf 'runtime=%s\n' "$runtime_dir"
printf 'nodeImage=%s\n' "$node_image"
printf 'composeProject=%s\n' "$project_name"

docker compose -f "$compose_file" up -d --quiet-pull cardano-node

deadline=$((SECONDS + deadline_seconds))
while (( SECONDS < deadline )); do
  docker compose -f "$compose_file" logs --no-color cardano-node > "$log_dir/cardano-node.log" 2>&1 || true

  if grep -Eq 'AesonException|CardanoProtocolInstantiationError|GenesisDecodeError|OtherPermissionsExist|required file not found' "$log_dir/cardano-node.log"; then
    printf 'verdict=failed\nlogPath=%s\n' "$log_dir/cardano-node.log" >&2
    cat "$log_dir/cardano-node.log" >&2
    exit 1
  fi

  if grep -Eq 'Net\.Server\.Local\.Started|Started opening Chain DB|Opened db with' "$log_dir/cardano-node.log"; then
    printf 'verdict=accepted\nlogPath=%s\n' "$log_dir/cardano-node.log"
    exit 0
  fi

  container_id=$(docker compose -f "$compose_file" ps -q cardano-node || true)
  container_running=false
  if [[ -n $container_id ]]; then
    container_running=$(docker inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || true)
  fi
  if [[ $container_running != true ]]; then
    printf 'verdict=failed\nreason=container-exited\nlogPath=%s\n' "$log_dir/cardano-node.log" >&2
    cat "$log_dir/cardano-node.log" >&2
    exit 1
  fi

  sleep "$poll_seconds"
done

docker compose -f "$compose_file" logs --no-color cardano-node > "$log_dir/cardano-node.log" 2>&1 || true
printf 'verdict=failed\nreason=timeout\nlogPath=%s\n' "$log_dir/cardano-node.log" >&2
cat "$log_dir/cardano-node.log" >&2
exit 1
