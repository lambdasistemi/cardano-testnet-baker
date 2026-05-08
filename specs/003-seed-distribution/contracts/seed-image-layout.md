# Contract: Seed Image Filesystem Layout

**Feature**: [../spec.md](../spec.md)

This contract specifies what a downstream consumer finds inside the
published image. Anything outside this list is not part of the contract
and may change without notice.

## Image base

`scratch` (no shell, no libc, no `/bin/sh`). The image carries one layer
whose root contains exactly the tree below.

## Tree

```text
/
└── seed/
    ├── chain-db/
    │   ├── immutable/
    │   ├── ledger/
    │   └── volatile/
    ├── genesis/
    │   ├── alonzo-genesis.json
    │   ├── byron-genesis.json
    │   ├── conway-genesis.json
    │   ├── shelley-genesis.json
    │   └── config.json
    ├── pools/
    │   └── pool-<name>/
    │       └── keys/
    │           ├── cold.skey
    │           ├── cold.vkey
    │           ├── kes.skey
    │           ├── opcert.cert
    │           ├── stake.skey
    │           ├── stake.vkey
    │           └── vrf.skey
    ├── utxo-keys/
    │   ├── genesis.<N>.addr.info
    │   └── genesis.<N>.skey
    ├── metadata.json
    └── synthesis-report.json   # observation block stripped (deterministic projection)
```

The file names mirror the baker's filesystem output verbatim
(see Feature 002's `examples/scenarios/local-fast.json` bake under
`tmp/bakes/`); they are the names cardano-node accepts directly via
`--shelley-operational-certificate opcert.cert`,
`ByronGenesisFile = "byron-genesis.json"` in `config.json`, etc. A
consumer can `COPY --from=seed /seed/genesis/byron-genesis.json
/configs/<pool>/configs/byron-genesis.json` without any rename layer.

The image's `synthesis-report.json` is the deterministic projection
described in [../research.md §8](../research.md): the original
`observation` block — `host`, `startedAt`, `completedAt`,
`wallTimeMilliseconds` — is removed at image-build time via
`jq 'del(.observation)'`. The remaining fields (`scenarioId`,
`scenarioDigest`, `bakerVersion`, `slotCount`, `profile`, and the full
`chainDb.*` size facts) are byte-identical across rebuilds.

Consumers that need producer-side wall-clock measurements must read the
unpackaged bake output from a CI run — the image does not carry them.

## File-mode contract

- Directories: `0755`
- Files: `0644`
- No setuid/setgid bits.
- No symlinks — `/seed/<x>` is a real file or directory at the
  image's filesystem root. The layer tar contains the materialised
  tree; there is no Nix-store indirection a consumer has to reason
  about.
- Consumers that need the stricter `0600` mode for private keys
  (KES, VRF, cold, stake) must `chmod 0600` after `COPY --from=`.

## Timestamp contract

The contract is *deterministic*, not literal-epoch-zero, because
`dockerTools.streamLayeredImage` packs layer tar entries with
`tar --mtime="@$SOURCE_DATE_EPOCH"` and `SOURCE_DATE_EPOCH` is fixed
per layer by upstream nixpkgs:

- Image config carries `created = "1970-01-01T00:00:00Z"` (set
  explicitly by `mkSeedImage`).
- The customisation layer's tar entries carry mtime
  `1980-01-01T00:00:00Z` (the `SOURCE_DATE_EPOCH = 315532800` that
  dockerTools' tar floor uses for pre-DOS-epoch safety).

Both timestamps are *fixed per build* — host wall-clock time never
leaks into either, so two rebuilds of the same scenario produce
byte-identical layer tars and byte-identical manifest digests.

Any host-clock mtime in the artifact (any value other than the two
above) is a determinism bug.

## Owner contract

All files are owned by `0:0`. Consumers that mount under a non-root
user must `chown` after copy.

## Empty directories

`chain-db/{immutable, ledger, volatile}` exist as directories even when
the scenario does not enable synthesis. (Without synthesis, the
directories are empty placeholders; the consumer's `cardano-node`
treats this as a fresh ChainDB.)

## What is NOT included

- No `cardano-node` binary.
- No `cardano-cli` binary.
- No shell.
- No `topology.json`; topology is per-deployment and the consumer's
  concern.
- No image entrypoint; this image is consumed by `COPY --from=`, not
  run.

`config.json` *is* shipped (under `seed/genesis/`) because it carries
the genesis-file name pointers (`ByronGenesisFile`,
`AlonzoGenesisFile`, etc.) that match the file names alongside it.
Consumers that override logging, P2P, or hard-fork settings layer
their adjustments on top of this baseline rather than starting from
scratch.
