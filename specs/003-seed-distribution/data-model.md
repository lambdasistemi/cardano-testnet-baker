# Data Model: Synthesized ChainDB Seed Distribution

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Date**: 2026-05-08

This file defines the entities and value types involved in the publish
flow. "Data" here means image layout, identifier strings, and CI
artifacts — not row-shaped persistent records.

## Entities

### Scenario

| Field | Type | Source | Notes |
|---|---|---|---|
| `name` | `String` | committed `examples/scenarios/<name>.json` filename | unique per-repo identifier; sole user-facing scenario handle |
| `digest` | `Hex64` | `metadata.json.inputDigest`, emitted by Feature 002 | SHA-256 of the canonical scenario JSON. Identical hex to `synthesis-report.json.scenarioDigest`. The field name in `metadata.json` is `inputDigest`; the consumer-facing tag fragment is named `<scenarioDigest>`. Tag derivation reads `inputDigest`. |

### Baker build identity

| Field | Type | Source | Notes |
|---|---|---|---|
| `commitShaFull` | `Hex40` | `git rev-parse HEAD` at build time | full Git SHA |
| `commitShaShort` | `Hex7` | `git rev-parse --short=7 HEAD` | 7 chars, ecosystem-standard |
| `bakerVersion` | `String` | `metadata.json.bakerVersion`, emitted by Feature 002 | retained for reproducer use, not for tag derivation |

### Seed payload

The image's filesystem under `/seed/`. This is the directory the
baker writes when invoked as `cardano-testnet-baker bake --scenario <s>
--out <dir>`, with one transformation: `synthesis-report.json` is
projected to remove the `observation` block before it enters the image
(see FR-002, FR-012). All other files pass through byte-identically.

```text
/seed/
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
│   └── pool-<n>/{kes.skey, vrf.skey, cold.skey, op.cert, stake.skey, stake.vkey, …}
├── utxo-keys/
│   └── faucet-<n>/{utxo.skey, utxo.vkey, address}
├── metadata.json
└── synthesis-report.json   # observation block stripped; deterministic
```

The on-disk projection is computed at image-build time as
`jq 'del(.observation)' synthesis-report.json` — no Haskell change.

### Seed image

| Field | Type | Notes |
|---|---|---|
| `repository` | `String` | `ghcr.io/lambdasistemi/cardano-testnet-seed` |
| `primaryTag` | `String` | `<scenario.name>-<scenario.digest>` |
| `secondaryTag` | `String` | `<scenario.name>-sha-<commitShaShort>` |
| `manifestDigest` | `String` | `sha256:<hex64>`, computed by the registry from layer + config bytes |
| `platform` | `String` | `linux/amd64`, single-arch |
| `created` | `String` | `1970-01-01T00:00:00Z` (epoch zero, for determinism) |
| `payloadRoot` | `String` | `/seed/` |
| `payloadBytes` | `Int` | size of `/seed/` tar layer; recorded in CI logs for sanity |

### Publish run

| Field | Type | Source | Notes |
|---|---|---|---|
| `scenarios` | `[Scenario]` | enumeration of `examples/scenarios/*.json` | not hardcoded |
| `commit` | `Baker build identity` | workflow context | one per CI run |
| `acceptanceVerdict` | `Enum {accepted, rejected}` | output of `compose/acceptance/run.sh` against the extracted `/seed/` | gate; `rejected` skips push |
| `pushOutcome` | `Enum {primaryOnly, both, none}` | per-scenario | `primaryOnly` is treated as failure for the whole job |

## Identifier rules

### Primary tag — content addressable

- Format: `<scenario.name>-<scenario.digest>`.
- Examples: `local-fast-3a9f…b2c1`, `normal-7e80…0f44`.
- Guarantee: re-resolves to the same `manifestDigest` for the lifetime of
  the namespace.
- Allowed characters: `[a-z0-9-]`. The scenario digest is lowercase hex;
  scenario names are lowercase ASCII.

### Secondary tag — commit traceable

- Format: `<scenario.name>-sha-<commitShaShort>`.
- Examples: `local-fast-sha-832deb6`, `normal-sha-832deb6`.
- Guarantee: distinguishes builds at different baker commits even when
  `scenario.digest` is unchanged.

### Forbidden tags

- `latest`
- `main`, `master`, any branch name
- `next`, `dev`, `prod`
- Anything that does not contain either `scenario.digest` or
  `commitShaShort`.

CI MUST refuse to push such tags; the publish script MUST validate
inputs against this rule before invoking `skopeo`.

## State transitions

```text
[scenario JSON committed]
    │
    │ baker bake
    ▼
[/seed/ directory + metadata.json with inputDigest (= consumer-facing scenarioDigest)]
    │
    │ pkgs.dockerTools.buildLayeredImage
    ▼
[oci-archive on disk, manifest digest D]
    │
    │ extract /seed/ → tmpfs, run compose/acceptance/run.sh
    ▼
[verdict ∈ {accepted, rejected}]
    │ rejected ──▶ FAIL job, no push
    │ accepted
    ▼
[skopeo copy → primaryTag] ──▶ [skopeo copy → secondaryTag]
    │ primary fail ──▶ FAIL job
    │ secondary fail ──▶ FAIL job (primary remains attached, idempotent re-run fixes it)
    ▼
[both tags attached to manifest digest D in registry]
```

## Invariants

- `manifestDigest` is a pure function of (scenario JSON + baker SHA +
  pinned nixpkgs + pinned dockerTools recipe).
- For the same `scenario.digest` and the same `manifestDigest`, two
  builds at *different* baker SHAs are valid; the secondary tag
  distinguishes them.
- `acceptanceVerdict = accepted` is a precondition for any push.
- No moving tag exists in the namespace at any point in time.
