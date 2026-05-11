#!/usr/bin/env bash
# Adapter that turns a baker output directory into the per-pool runtime
# layout the antithesis compose stack feeds its cardano-node containers
# from.  This is what the `configurator` service in
# cardano-node-antithesis produces today; we reproduce its shape outside
# the deterministic baker so `bake` stays a pure function of the
# scenario.
#
# Output layout (under <runtime>):
#
#   p<n>/configs/{config.json,topology.json,*-genesis.json}
#   p<n>/keys/{kes.skey,vrf.skey,opcert.cert}
#   utxo-keys/...   (copied from the bake for faucet/UTxO consumers)
set -euo pipefail

usage() {
  printf 'usage: %s <baked-output-dir> <runtime-dir>\n' "$0" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

baked_dir=$1
runtime_dir=$2

if [[ ! -d $baked_dir ]]; then
  printf 'baked output directory not found: %s\n' "$baked_dir" >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

mkdir -p "$runtime_dir"

# Resolve pool list deterministically from the bake.  The baker writes
# pools/<label>/keys/...; we map them positionally to p1..pN to match
# the antithesis compose service names.
mapfile -t pool_labels < <(find "$baked_dir/pools" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
num_pools=${#pool_labels[@]}

if (( num_pools < 1 )); then
  printf 'no pools found under %s/pools\n' "$baked_dir" >&2
  exit 1
fi

# Shared genesis directory: patched once, then copied per pool so each
# pool sees an identical genesis hash.
shared_dir="$runtime_dir/.shared/genesis"
mkdir -p "$shared_dir"
cp "$baked_dir"/genesis/* "$shared_dir/"

# Patch shared genesis with a dynamic systemStart / startTime aligned to
# a 120s boundary, mirroring the configurator's rounding.
system_start_unix=${ACCEPTANCE_START_TIME:-$(( ( $(date -u +%s) / 120 ) * 120 ))}
system_start_iso=$(date -u -d "@${system_start_unix}" +%Y-%m-%dT%H:%M:%SZ)

tmp=$(mktemp)
jq --arg s "$system_start_iso" '.systemStart = $s' \
  "$shared_dir/shelley-genesis.json" > "$tmp"
mv "$tmp" "$shared_dir/shelley-genesis.json"

tmp=$(mktemp)
jq --argjson t "$system_start_unix" '.startTime = $t' \
  "$shared_dir/byron-genesis.json" > "$tmp"
mv "$tmp" "$shared_dir/byron-genesis.json"

# Configurator-equivalent config.json shape:
#   - drop *GenesisHash, hasEKG, options.mapBackends (no-ops on baker
#     output today but kept for byte-shape parity)
#   - add PeerSharing (default true)
#   - add LedgerDB V2InMemory (configurator default when UTXO_HD_WITH is
#     unset)
peer_sharing=${ACCEPTANCE_PEER_SHARING:-true}
tmp=$(mktemp)
jq --argjson peerSharing "$peer_sharing" '
  del(.AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash)
  | del(.hasEKG)
  | del(.options.mapBackends)
  | .PeerSharing = $peerSharing
  | .LedgerDB = { Backend: "V2InMemory" }
  ' "$shared_dir/config.json" > "$tmp"
mv "$tmp" "$shared_dir/config.json"

# Configurator-equivalent alonzo bump (room for asteria scripts).
tmp=$(mktemp)
jq '
  .maxTxExUnits.exUnitsMem    = 14000000
  | .maxTxExUnits.exUnitsSteps  = 14000000000
  | .maxBlockExUnits.exUnitsMem = 80000000
  | .maxBlockExUnits.exUnitsSteps = 64000000000
  ' "$shared_dir/alonzo-genesis.json" > "$tmp"
mv "$tmp" "$shared_dir/alonzo-genesis.json"

# Per-pool layout.
for idx in "${!pool_labels[@]}"; do
  pool_label=${pool_labels[$idx]}
  pool_num=$(( idx + 1 ))
  pool_runtime="$runtime_dir/p${pool_num}"
  mkdir -p "$pool_runtime/configs" "$pool_runtime/keys"

  cp "$shared_dir"/* "$pool_runtime/configs/"

  # Ring topology: each pool sees the previous and next pool by hostname
  # p<n>.example, matching the antithesis compose hostnames.
  prev=$(( pool_num - 1 ))
  next=$(( pool_num + 1 ))
  if (( prev < 1 )); then prev=$num_pools; fi
  if (( next > num_pools )); then next=1; fi
  jq -n \
    --arg prev "p${prev}.example" \
    --arg next "p${next}.example" \
    '{
      localRoots: [{
        accessPoints: [
          { address: $prev, port: 3001 },
          { address: $next, port: 3001 }
        ],
        advertise: true,
        trustable: true,
        valency: 2
      }],
      publicRoots: [],
      useLedgerAfterSlot: 0
    }' > "$pool_runtime/configs/topology.json"

  # Per-pool keys: baker emits cold/stake too, antithesis only mounts
  # kes/vrf/opcert.  Copy just those three so the layout matches.
  pool_keys="$baked_dir/pools/${pool_label}/keys"
  cp "$pool_keys/kes.skey"    "$pool_runtime/keys/kes.skey"
  cp "$pool_keys/vrf.skey"    "$pool_runtime/keys/vrf.skey"
  cp "$pool_keys/opcert.cert" "$pool_runtime/keys/opcert.cert"
done

# UTxO keys (faucet) for any downstream consumer (tx-generator etc.).
if [[ -d "$baked_dir/utxo-keys" ]]; then
  mkdir -p "$runtime_dir/utxo-keys"
  cp -R "$baked_dir/utxo-keys/." "$runtime_dir/utxo-keys/"
fi

printf 'pools=%s\n' "$num_pools"
printf 'systemStart=%s\n' "$system_start_iso"
printf 'runtime=%s\n' "$runtime_dir"
