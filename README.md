# cardano-testnet-baker

Deterministic Cardano testnet artifact baker.

Reads a declarative **scenario JSON** describing the network (initial stake,
producers, faucets, era schedule, optional ChainDB synthesis) and produces a
versioned, reproducible artifact set:

- Genesis files (Byron, Shelley, Alonzo, Conway)
- Pool keys (KES, VRF, cold, operational certificate, stake)
- Faucet (UTxO) keys with matching `initialFunds` entries
- Optional synthesized **ChainDB seed** that already spans the epochs Amaru
  bootstrap snapshots anchor to

Targets:

| Target | How |
|---|---|
| Local CLI | `nix run github:lambdasistemi/cardano-testnet-baker -- scenario validate <scenario.json>` |
| OCI image | published to `ghcr.io/lambdasistemi/cardano-testnet-baker:<sha>` |
| Native binary | DEB / RPM / AppImage / Homebrew tap (forthcoming) |

## Status

Features 001, 002, and 003 are landed.

- **Feature 001** — scenario JSON schema, semantic validation, and
  deterministic `bake` output (genesis files, pool keys, faucet keys,
  metadata). See `schemas/scenario/v1.schema.json` and
  `examples/scenarios/{local-fast,normal}.json`.
- **Feature 002** — optional ChainDB seed synthesis emitted alongside
  the bake artifacts, plus a Docker Compose node-startup acceptance
  harness. Design material lives in
  [`specs/002-chaindb-synthesis/`](./specs/002-chaindb-synthesis/).
- **Feature 003** — every push publishes the per-scenario seed as a
  deterministic OCI image to
  `ghcr.io/lambdasistemi/cardano-testnet-seed`, gated on a
  determinism check and image-driven compose acceptance. See
  [`docs/seed-distribution.md`](./docs/seed-distribution.md) for the
  consumer / maintainer / reviewer flows. Tracked under
  [PR #12](https://github.com/lambdasistemi/cardano-testnet-baker/pull/12).

## Scenario Validation

Validate every committed example against the published JSON Schema:

```sh
just validate-scenarios
```

Validate a scenario with the CLI semantic checks:

```sh
nix run . -- scenario validate examples/scenarios/local-fast.json
```

## Baking

Bake the `local-fast` example:

```sh
just bake-local-fast
```

Bake both committed examples:

```sh
just bake-examples
```

The output directory contains `genesis/`, `pools/`, `utxo-keys/`, and
`metadata.json`. The metadata records deterministic input and artifact digests.

## ChainDB Seed Synthesis

Synthesis is an optional scenario feature. A synthesis-enabled bake will keep
the existing genesis, pool, faucet, and metadata outputs and add:

- `chain-db/` with the immutable synthesized seed
- `synthesis-report.json` with wall time, ChainDB size on disk, packaged-size
  proxy, file count, scenario identity, input digest, and baker version

The deterministic seed output is derived from the scenario, baker version, and
pinned dependencies. Host-dependent observations, such as wall time, are kept in
the synthesis report rather than deterministic metadata.

Inspect the pinned upstream synthesizer exposed by this flake:

```sh
nix run .#db-synthesizer -- --help
```

The compose seed acceptance flow copies generated assets and the ChainDB seed
into private writable runtime storage before starting `cardano-node`. The
generated artifact directory remains immutable during acceptance.

## Determinism

Run the Nix check that bakes both committed examples twice, recursively diffs
the output bytes, and compares file modes:

```sh
nix build .#checks.x86_64-linux.example-bake-determinism
```

## Compose Acceptance

Start a pinned `cardano-node 10.7.1` image from the baked assets:

```sh
just acceptance-local-fast
just acceptance-normal
```

The harness copies baked assets into a temporary runtime directory, patches only
runtime `systemStart` and Byron `startTime`, mounts the runtime assets read-only,
and waits for the node startup acceptance signal.

## Consuming the seed image

Every push publishes a deterministic OCI seed image per committed
scenario to `ghcr.io/lambdasistemi/cardano-testnet-seed`, under both
a content-derived primary tag (`<scenario>-<scenario-digest>`) and a
commit-traceable secondary tag (`<scenario>-sha-<commit-sha-short>`).
A downstream Dockerfile pulls a seed with four `COPY --from=` lines —
one per stable top-level directory under `/seed/` (`chain-db`,
`genesis`, `pools`, `utxo-keys`):

```dockerfile
ARG SEED_REF=ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-sha-832deb6

FROM ${SEED_REF} AS seed
FROM ghcr.io/intersectmbo/cardano-node:10.7.1

COPY --from=seed /seed/chain-db   /db
COPY --from=seed /seed/genesis    /genesis
COPY --from=seed /seed/pools      /pools
COPY --from=seed /seed/utxo-keys  /utxo-keys
```

See [`docs/seed-distribution.md`](./docs/seed-distribution.md) for
the maintainer dry-run flow, the offline-reviewer verification
walkthrough, and pinning guidance for downstream stacks.

## Development

```sh
nix develop          # cabal, GHC 9.12.3, fourmolu, hlint, hls
just --list          # available recipes
just CI              # mirrors the GitHub CI pipeline
```

## License

Apache-2.0. See [LICENSE](./LICENSE).
