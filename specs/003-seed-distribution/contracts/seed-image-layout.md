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
    │   ├── alonzo.json
    │   ├── byron.json
    │   ├── conway.json
    │   └── shelley.json
    ├── pools/
    │   └── pool-N/
    │       ├── kes.skey
    │       ├── vrf.skey
    │       ├── cold.skey
    │       ├── op.cert
    │       ├── stake.skey
    │       └── stake.vkey
    ├── utxo-keys/
    │   └── faucet-N/
    │       ├── address
    │       ├── utxo.skey
    │       └── utxo.vkey
    ├── metadata.json
    └── synthesis-report.json   # observation block stripped (deterministic projection)
```

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
- No symlinks (the baker output is symlink-free; the image preserves
  that property).

## Timestamp contract

All inodes carry mtime `1970-01-01T00:00:00Z`. The image config also
declares `created = "1970-01-01T00:00:00Z"`. Any later mtime is a
determinism bug.

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
- No node configuration files (`config.json`, `topology.json`); these
  are the consumer's concern.
- No image entrypoint; this image is consumed by `COPY --from=`, not
  run.
