# Research: Scenario JSON Schema and Bake CLI MVP

## R-001: Cardano libraries and CHaP are in scope for Feature 001

**Decision**: Wire CHaP and iohk-nix crypto overlays in this feature, using
cardano-* package versions aligned with the pinned `cardano-node` image used by
compose acceptance.

**Rationale**: The feature must produce genesis files, pool keys, operational
certificates, faucet keys, and text envelopes that a real node accepts. That is
not a string-formatting problem. Using upstream Cardano libraries keeps the
implementation on the allowed mode-(b) path: custom orchestration in this repo,
upstream code consumed as libraries, no forks.

**Alternatives considered**:
- Keep CHaP out of scope and hand-render files: rejected because compose
  acceptance would catch invalid genesis/key material late and repeatedly.
- Shell out to `cardano-cli` random key generation: rejected because fresh
  randomness violates deterministic key derivation.
- Reuse the Python `testnet-generation-tool`: rejected by the Haskell-only
  project decision and because this repo exists to replace that runtime path.

## R-002: JSON Schema publication and validation

**Decision**: Publish `schemas/scenario/v1.schema.json` as the structural
contract and validate committed examples against it in CI with Nix-provided
`check-jsonschema`. The Haskell parser performs semantic validation that JSON
Schema cannot express cleanly.

**Rationale**: The constitution makes the bootstrapping/scenario JSON a public
compatibility contract. Schema validation catches missing fields, wrong shapes,
and unsupported enum values before the baker starts. Semantic validation then
checks cross-field invariants such as unique labels, funded address references,
and supported era schedules.

**Alternatives considered**:
- Rely only on Haskell decoding: rejected because downstream consumers need a
  language-neutral schema contract.
- Add a Haskell JSON Schema validator to the MVP CLI: rejected because schema
  validation is a CI/public-contract concern here, while the CLI's critical
  role is semantic validation plus deterministic baking.
- Put every invariant into JSON Schema: rejected because deterministic key-label
  uniqueness and Cardano-specific cross-field checks are clearer and safer in
  typed Haskell validation.

## R-003: Deterministic key derivation

**Decision**: Derive each key seed with HKDF/HMAC-SHA256 using domain-separated
inputs: `cardano-testnet-baker/v1`, `scenario.seed`, key role, and key label.
Feed derived bytes into upstream Cardano key constructors/renderers.

**Rationale**: This makes key material stable across hosts while preventing
role or label collisions from sharing raw seed material. The same derivation
function covers KES, VRF, cold, stake, operational-certificate source material,
and faucet/UTxO keys.

**Alternatives considered**:
- Store key material directly in the scenario: rejected because the scenario
  should be compact and seed-driven, and because it would make rotation harder.
- Derive by hashing string concatenation once: rejected because HKDF gives
  explicit domain separation and future expansion without changing semantics.

## R-004: `systemStart` is patched only for acceptance

**Decision**: The baked artifact keeps `systemStart` and Byron `startTime` as
non-run-specific placeholders or metadata-declared patch points. The compose
acceptance harness copies the baked assets into a temporary directory, patches
start times there, then starts the cluster.

**Rationale**: The artifact must span runs. A node cannot start against a
useful testnet without a current enough start time, so acceptance needs a patch,
but that patch must not feed back into the baked artifact or determinism check.

**Alternatives considered**:
- Bake the current time: rejected by constitution Principle I.
- Skip node startup acceptance: rejected by constitution Principle VI.

## R-005: Atomic output and canonical files

**Decision**: Bake into a temporary sibling directory, write all files with
stable relative paths and canonical JSON formatting, compute metadata digests,
then rename into the final output directory. Non-empty output directories are
rejected.

**Rationale**: A partial artifact tree can look valid to downstream consumers.
Atomic publishing and strict empty-output handling make interrupted bakes safe
and make two-run diffs meaningful.

**Alternatives considered**:
- Merge into an existing output directory: rejected because stale files could
  survive and break determinism.
- Stream files directly into final paths: rejected because interruption leaves
  ambiguous state.

## R-006: Compose cluster acceptance scope

**Decision**: CI runs a minimal Docker Compose acceptance harness for each
committed example scenario. The harness mounts generated genesis/config/key
assets, starts the intended node topology far enough to validate initial chain
state, and fails on node startup, genesis, configuration, or key validation
errors.

**Rationale**: This is the project-level proof that the assets are actually
usable. It is stronger than schema validation and weaker than ChainDB synthesis,
which remains out of scope.

**Alternatives considered**:
- Run only `cardano-cli` offline validation: rejected because it does not prove
  a node accepts the full startup configuration.
- Run a long-lived cluster convergence test: deferred; Feature 001 needs
  startup acceptance only.
