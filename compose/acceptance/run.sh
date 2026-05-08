#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s <scenario-name> <input>\n' "$0" >&2
  printf '  <input> is one of:\n' >&2
  printf '    <baked-output-dir>\n' >&2
  printf '    docker-archive:<path-to-tar.gz>\n' >&2
  printf '    oci-archive:<path-to-tar.gz>\n' >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

scenario_name=$1
input=$2

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tmp_root=${ACCEPTANCE_TMP_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/cardano-testnet-baker-acceptance.XXXXXX")}
runtime_dir="$tmp_root/runtime"
project_name="ctb-${scenario_name//[^[:alnum:]]/-}-$$"
log_dir=${ACCEPTANCE_LOG_DIR:-"$PWD/tmp/acceptance-logs/$project_name"}
compose_file="$script_dir/docker-compose.yaml"
node_image=${CARDANO_NODE_IMAGE:-ghcr.io/intersectmbo/cardano-node@sha256:3275d357053d21f3220f74b0854fd584e1fe322dfa1bbb78effd760c3191d14c}
deadline_seconds=${ACCEPTANCE_DEADLINE_SECONDS:-30}
poll_seconds=${ACCEPTANCE_POLL_SECONDS:-1}

# Reserved for archive-mode mktemp (set when input is an archive URI).
archive_extract_dir=

cleanup() {
  docker compose -f "$compose_file" down --volumes --remove-orphans >/dev/null 2>&1 || true
  if [[ ${ACCEPTANCE_KEEP_TMP:-false} != true ]]; then
    rm -rf "$tmp_root"
    if [[ -n $archive_extract_dir && -d $archive_extract_dir ]]; then
      rm -rf "$archive_extract_dir"
    fi
  fi
}
trap cleanup EXIT

# Resolve the input into a directory of bake artifacts. Archive
# inputs (`docker-archive:`/`oci-archive:`) are extracted into a
# tmpfs-backed mktemp dir (with `$TMPDIR` fallback) and the single
# layer's `seed/` subtree is the resulting `baked_output_dir`.
resolve_input_kind() {
  case "$1" in
    docker-archive:*|oci-archive:*) printf 'archive' ;;
    *) printf 'dir' ;;
  esac
}

# Extract the single layer of an OCI archive into
# `<extract_dir>/seed-root/seed/`. The function intentionally does
# not allocate the extract dir itself or use command substitution
# in the caller — the parent shell allocates it ahead of time so
# `archive_extract_dir` is set before `extract_archive_seed`
# returns, regardless of any failure mode, ensuring the cleanup
# trap can always remove it.
extract_archive_seed() {
  local uri=$1
  local extract_dir=$2

  local skopeo_dir="$extract_dir/skopeo-dir"
  mkdir -p "$skopeo_dir"

  if ! skopeo copy "$uri" "dir:$skopeo_dir" >/dev/null; then
    printf 'skopeo copy %s -> dir failed\n' "$uri" >&2
    return 1
  fi

  # `dir:` form writes one file per layer (uncompressed tar) plus
  # `manifest.json`, `version`, and the config blob. The seed image
  # carries exactly one layer; locate it by parsing manifest.json
  # rather than by filename glob.
  local manifest="$skopeo_dir/manifest.json"
  if [[ ! -f $manifest ]]; then
    printf 'skopeo dir output missing manifest.json: %s\n' "$skopeo_dir" >&2
    return 1
  fi

  local layer_count
  layer_count=$(jq -r '.layers | length' "$manifest")
  if [[ $layer_count != 1 ]]; then
    printf 'expected exactly one layer in archive, got %s\n' "$layer_count" >&2
    return 1
  fi

  local layer_digest layer_path
  layer_digest=$(jq -r '.layers[0].digest' "$manifest")
  # `dir:` format names blob files after their digest, with no
  # `sha256:` prefix.
  layer_path="$skopeo_dir/${layer_digest#sha256:}"
  if [[ ! -f $layer_path ]]; then
    printf 'layer blob not found: %s\n' "$layer_path" >&2
    return 1
  fi

  local seed_root="$extract_dir/seed-root"
  mkdir -p "$seed_root"
  tar -xf "$layer_path" -C "$seed_root"

  if [[ ! -d "$seed_root/seed" ]]; then
    printf 'archive does not carry /seed/ at root\n' >&2
    return 1
  fi
}

input_kind=$(resolve_input_kind "$input")
case $input_kind in
  archive)
    # Allocate the extraction dir in the *parent* shell so the
    # cleanup trap can see it even if `extract_archive_seed`
    # fails mid-way. Using command substitution to receive a
    # path back from the helper would run it in a subshell and
    # leak the dir.
    archive_extract_dir=$(
      mktemp -d -p /dev/shm cardano-testnet-baker-archive.XXXXXX 2>/dev/null \
        || mktemp -d "${TMPDIR:-/tmp}/cardano-testnet-baker-archive.XXXXXX"
    )
    extract_archive_seed "$input" "$archive_extract_dir"
    baked_output_dir="$archive_extract_dir/seed-root/seed"
    ;;
  dir)
    baked_output_dir=$input
    if [[ ! -d $baked_output_dir ]]; then
      printf 'baked output directory not found: %s\n' "$baked_output_dir" >&2
      exit 1
    fi
    ;;
  *)
    printf 'unsupported input kind: %s\n' "$input_kind" >&2
    exit 2
    ;;
esac

mkdir -p "$runtime_dir" "$log_dir"
cp -R "$baked_output_dir/." "$runtime_dir/"
cp "$script_dir/topology/topology.json" "$runtime_dir/topology.json"
"$script_dir/patch-system-start.sh" "$runtime_dir"

export ACCEPTANCE_RUNTIME_DIR=$runtime_dir
export CARDANO_NODE_IMAGE=$node_image
export COMPOSE_PROJECT_NAME=$project_name

printf 'scenario=%s\n' "$scenario_name"
printf 'inputKind=%s\n' "$input_kind"
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
