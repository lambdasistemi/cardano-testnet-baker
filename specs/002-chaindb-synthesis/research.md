# Research: ChainDB Seed Synthesis Measurement MVP

## R-001: Upstream synthesizer source

**Decision**: Expose the stock `db-synthesizer` executable from the pinned
`ouroboros-consensus` source package already declared in `cabal.project`.

**Rationale**: The repo is already aligned to cardano-node 10.7.1 and pins
`ouroboros-consensus` for this future feature. The sibling `amaru-bootstrap`
repo exposes `project.hsPkgs.ouroboros-consensus.components.exes.db-synthesizer`
without patching upstream code.

**Alternatives considered**:

- Vendor or fork the synthesizer: rejected by the constitution.
- Reimplement ChainDB generation in this repo: rejected because the stock tool
  already exists and is the most direct acceptance target.

## R-002: Synthesis input shape

**Decision**: Generate the synthesizer bulk credentials file from baked pool
artifacts: operational certificate, VRF signing key, and KES signing key.

**Rationale**: `db-synthesizer` accepts the node config and a
bulk-credentials JSON array. The existing bake output already contains the
per-pool materials needed to build that file deterministically.

**Alternatives considered**:

- Add a separate credential input file to the CLI: rejected because it would be
  a hidden output-affecting input.
- Keep a hand-written fixture for synthesis: rejected because it would drift
  away from the scenario being baked.

## R-003: Scenario schema extension

**Decision**: Add an optional `synthesis` object to scenario schema v1 with an
`enabled` flag and an explicit `slotCount`.

**Rationale**: Optional additive fields can preserve existing genesis-only
scenarios while making synthesis parameters visible and deterministic for
scenarios that request a seed.

**Alternatives considered**:

- Infer slot count from epoch length: rejected because the output-affecting
  count would be implicit and hard to change per scenario.
- Always synthesize for every scenario: rejected because routine CI may need a
  smaller path than realistic measurement.

## R-004: Measurement separation

**Decision**: Keep deterministic artifact metadata separate from a synthesis
measurement report that contains host-dependent observations such as wall time.

**Rationale**: ChainDB bytes and file inventories can be deterministic, but
wall time depends on the runner. Mixing wall time into deterministic metadata
would break two-run artifact comparison or require ignoring part of the file.

**Alternatives considered**:

- Put all measurements in `metadata.json`: rejected because timing would make
  metadata non-deterministic.
- Skip timing: rejected because synthesis duration is one of the open storage
  strategy inputs.

## R-005: Packaged-size proxy

**Decision**: Measure a deterministic compressed tarball proxy for the seed
directory without publishing it as the final distribution format.

**Rationale**: The feature needs an OCI-layer-size signal before choosing a
publishing strategy. A stable archive-size proxy is enough for comparison and
keeps GHCR/S3/release asset decisions out of scope.

**Alternatives considered**:

- Build and push OCI images now: rejected as a separate distribution feature.
- Record only raw disk usage: rejected because compressed transport size is
  also needed for storage decisions.

## R-006: Acceptance copy model

**Decision**: Compose acceptance copies the generated seed into a private
writable database directory before starting the node.

**Rationale**: The generated seed is an immutable artifact, but cardano-node
mutates its database while opening and extending it. Downstream clusters also
need one writable copy per node, not a shared mutable seed.

**Alternatives considered**:

- Mount the generated seed read-only as the live database: rejected because
  node startup requires writable database state.
- Share one writable database between producers: rejected because it is not a
  safe downstream topology.

## R-007: Routine and realistic measurement paths

**Decision**: Use a small synthesis-enabled scenario for routine PR acceptance
and a realistic-epoch measurement path before choosing storage.

**Rationale**: The project needs both fast feedback and realistic size data.
The sibling project has precedent for synthesizing 300000 slots against an
86400-slot epoch fixture, while short-epoch sparse chains may need careful
slot-count selection to produce useful immutable data.

**Alternatives considered**:

- Run only the tiny path: rejected because it does not answer the storage-size
  question.
- Run the realistic path on every PR unconditionally: rejected until measured,
  because it may make routine CI impractical.
