# Feature Specification: Synthesized ChainDB Seed Distribution

**Feature Branch**: `003-seed-distribution`
**Created**: 2026-05-08
**Status**: Draft
**Input**: User description: "Distribute the synthesized ChainDB seed as a versioned, consumable seed-only OCI image. Source ticket: https://github.com/lambdasistemi/cardano-testnet-baker/issues/11"

## User Scenarios & Testing

### User Story 1 — Antithesis stack maintainer pins a seed by content digest (Priority: P1)

An operator maintaining the Antithesis testnet compose stack (today
`lambdasistemi/amaru-bootstrap`, tomorrow other downstreams) needs to embed a
deterministic ChainDB seed into a `cardano-node` image. They want one stable
identifier to pin in their Dockerfile, and they need that identifier to refer
to content that will never silently change beneath them.

**Why this priority**: Without pinned distribution, every downstream consumer
must clone the baker repo, install Nix, run a multi-minute synthesis build,
and manually copy the resulting tree. That is the primary blocker called out
in issue #11 and the immediate reason the feature exists.

**Independent Test**: A reviewer with only Docker installed (no Nix, no
checkout of this repo) can write a `Dockerfile` that does
`COPY --from=ghcr.io/lambdasistemi/cardano-testnet-seed:<scenario>-<digest>
/seed/ /seed/`, build the image, run the project's compose acceptance harness
against the resulting tree, and observe `verdict=accepted`.

**Acceptance Scenarios**:

1. **Given** a published seed image tag of the form `<scenario>-<digest>`,
   **When** a downstream Dockerfile copies `/seed/` from it,
   **Then** the consumer image contains a complete artifact set (genesis
   files, pool keys, faucet keys, chain-db tree, metadata, synthesis report)
   with the exact byte content the baker produced.
2. **Given** the same `<scenario>-<digest>` tag is pulled twice from any
   host, **When** the manifest digests are compared, **Then** they are equal
   — the tag is content-addressable and never silently re-points.
3. **Given** a downstream PR that pins one such tag, **When** a baker change
   unrelated to that scenario is merged on `main`, **Then** the pinned tag
   continues to resolve to the same manifest digest and the downstream PR is
   not perturbed.
4. **Given** a consumer with only a stock Docker daemon, **When** they pull
   and consume a seed image, **Then** they require no Nix, no checkout of
   this repository, and no knowledge of the baker's internal toolchain.

---

### User Story 2 — Baker maintainer cuts a release for both committed scenarios (Priority: P1)

A maintainer pushing to `main` (or to a PR branch) needs the CI pipeline to
publish a fresh seed image for every committed scenario, so that downstream
PRs can immediately reference the new artifacts by tag without waiting for a
manual release process.

**Why this priority**: The downstream Antithesis wiring in
`amaru-bootstrap#15` is in flight and needs per-commit identifiers it can pin
in its compose stack. Per-commit publishing is also what closes the iteration
loop for the baker maintainer themselves.

**Independent Test**: A maintainer pushes a commit that does not change
scenario JSON. CI runs end-to-end, publishes images for both committed
scenarios, and the published manifest digests for those scenarios are
*identical* to the digests published from the prior commit (because the
scenarios did not change). A subsequent commit that *does* change a scenario
yields a different digest for that scenario only.

**Acceptance Scenarios**:

1. **Given** a push that touches no scenario JSON and no synthesis logic,
   **When** CI completes, **Then** the published seed image manifest digests
   for `local-fast` and `normal` match the previous push's digests.
2. **Given** a push that updates `examples/scenarios/normal.json`, **When**
   CI completes, **Then** the `normal` image's primary tag changes (because
   `<scenarioDigest>` changes) and the `local-fast` image's primary tag does
   not.
3. **Given** any successful CI run, **When** the maintainer inspects the
   registry, **Then** each scenario carries both a content-derived primary
   tag (`<scenario>-<scenarioDigest>`) and a per-commit secondary tag
   (`<scenario>-sha-<bakerCommitSha7>`); no `:latest`, `:main`, or other
   moving tag is published.
4. **Given** any push, including PR branches, **When** the build gate runs,
   **Then** publishing only proceeds after the existing compose acceptance
   harness has succeeded against the seed extracted from the *image about to
   be published*, not against an unpackaged baker output.

---

### User Story 3 — Offline reviewer verifies determinism end-to-end (Priority: P2)

A reviewer auditing the supply chain — for compliance, for an Antithesis run
post-mortem, or simply to keep the baker honest — needs to reproduce a
published image from source and confirm bit-identical output without trusting
the registry or the CI runner.

**Why this priority**: Determinism is the central baker promise (constitution
§II) and the reason consumers can pin by content digest at all. Verifiability
must be available to reviewers, not just asserted.

**Independent Test**: A reviewer checks out the baker at a published commit
SHA, runs the documented `bake` plus `package` flow on their own machine, and
the resulting image manifest digest equals the digest of the corresponding
tag in the registry.

**Acceptance Scenarios**:

1. **Given** a published seed image tag and the baker commit SHA it was
   built from, **When** the reviewer reproduces the build offline, **Then**
   their local image manifest digest equals the published manifest digest.
2. **Given** a published image, **When** the reviewer extracts `/seed/`,
   **Then** the bytes match what the baker writes to its scenario output
   directory for the same scenario at the same commit.
3. **Given** a published image, **When** the reviewer reads
   `/seed/metadata.json` and the deterministic projection of
   `/seed/synthesis-report.json` (without the host-dependent
   `observation` block, see FR-002), **Then** they see the same
   `slotCount`, `profile`, `scenarioDigest`, and `chainDb.*` size
   facts that `specs/002-chaindb-synthesis/quickstart.md` records as
   measurement evidence for that scenario at that baker version.
   Producer-side wall-clock fields are intentionally not in the image.

---

### Edge Cases

- **Scenario added or removed from `examples/scenarios/`** — the publish set
  must follow the committed example list exactly; adding a new committed
  example automatically extends publishing, removing one stops further
  publishing for that name (existing tags remain).
- **Scenario digest collision across baker versions** — two different baker
  versions producing the same `<scenario>-<scenarioDigest>` primary tag is
  expected when the scenario JSON is unchanged and the synthesis output is
  byte-identical; the secondary `sha-<bakerCommitSha7>` tag distinguishes
  the builds for human traceability.
- **Failing compose acceptance against the pulled image** — must fail the
  build gate. Publishing must not occur if the artifact-under-test fails its
  own acceptance harness.
- **Registry write failure** — must fail the build gate visibly; partial tag
  uploads (primary published, secondary missing, or vice versa) must be
  treated as failure.
- **Re-running the same commit** — must be a no-op at the registry: the same
  manifest digest is re-pushed, no new image content is created.
- **Consumer pulls a tag that was never published** — Docker daemon's normal
  `manifest unknown` error is acceptable; this feature does not introduce a
  custom error path for missing tags.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST publish, for every committed example scenario
  (currently `local-fast` and `normal`), a single seed-only artifact whose
  payload is the deterministic baker output for that scenario at the current
  baker commit.
- **FR-002**: The published artifact's payload MUST be a directory tree
  rooted at `/seed/` containing the files the baker writes to its scenario
  output directory: `genesis/`, `pools/`, `utxo-keys/`, `chain-db/`,
  `metadata.json`, and a *deterministic projection* of
  `synthesis-report.json` (the `chain-db/` and `synthesis-report.json`
  entries appear when the scenario enables synthesis). The
  deterministic projection MUST drop the `observation` block (host,
  `startedAt`, `completedAt`, `wallTimeMilliseconds`) which Feature 002
  classifies as host-dependent and explicitly excludes from byte-for-byte
  equality (`specs/002-chaindb-synthesis/contracts/artifact-layout.md`,
  Determinism Rules). All other fields of the report — `scenarioId`,
  `scenarioDigest`, `bakerVersion`, `slotCount`, `profile`, `chainDb.*` —
  remain in the published copy.
- **FR-003**: Each published artifact MUST be addressable by a primary tag
  of the form `<scenario-name>-<scenarioDigest>`, where `<scenarioDigest>`
  is the canonical scenario hash sourced from `metadata.json.inputDigest`
  (the field name baker code uses today). The tag fragment is named
  `<scenarioDigest>` for consumer-facing clarity even though the source
  field is `inputDigest`; both refer to the SHA-256 of the canonical
  scenario JSON, identical hex to `synthesis-report.json.scenarioDigest`.
- **FR-004**: Each published artifact MUST also be addressable by a
  secondary tag of the form `<scenario-name>-sha-<bakerCommitSha7>` for
  human-traceable per-commit linkage.
- **FR-005**: The system MUST NOT publish moving tags. `latest`, `main`,
  branch names, and any other tag whose target can change without a content
  change are explicitly forbidden.
- **FR-006**: Re-running the publish flow at the same baker commit, with
  the same scenario JSON, MUST produce a byte-identical artifact manifest
  digest. This MUST be exercised by a determinism check in the build gate.
- **FR-007**: Before any artifact is published for a scenario, the existing
  Docker Compose acceptance harness MUST succeed against the seed extracted
  from the artifact about to be published. Publishing MUST NOT proceed if
  acceptance fails.
- **FR-008**: The publish flow MUST run on every push to `main` and on
  every pull-request branch.
- **FR-009**: A consumer MUST be able to obtain the seed using only a stock
  container runtime — no checkout of this repository and no Nix
  installation on the consumer host.
- **FR-010**: The repository MUST document, in a location reachable from
  the README, how a downstream consumer pins a seed artifact and copies
  `/seed/` into their own image.
- **FR-011**: The repository MUST publish enough material — the artifact
  identifier scheme, the layout under `/seed/`, and a worked compose-snippet
  example — for the paired wiring PR in `lambdasistemi/amaru-bootstrap` (its
  issue #15) to land without re-deciding any part of the contract.
- **FR-012**: The published artifact MUST carry, as part of its payload, a
  deterministic projection of the `synthesis-report.json` produced by
  Feature 002 (see FR-002), so a consumer can inspect the scenario's
  `slotCount`, `profile`, and `chainDb.*` size facts without re-running
  synthesis. The host-dependent wall-clock observation block is **not**
  part of the image; consumers requiring producer-side timing must read
  the unpackaged bake output from a CI run.
- **FR-013**: V1 MUST NOT add image signing. A follow-up issue MUST be
  filed to introduce cosign keyless signing (Sigstore Fulcio/Rekor via the
  GitHub Actions OIDC token) once basic publishing is proven, per the
  constitution's "smallest provable step" principle.
- **FR-014**: All published seed images MUST be retained indefinitely. No
  active pruning is configured. Per-commit secondary tags
  (`<scenario>-sha-<bakerCommitSha7>`) and content-derived primary tags
  (`<scenario>-<scenarioDigest>`) both remain resolvable for the lifetime of
  the GHCR namespace.
- **FR-015**: Artifact platform coverage MUST be `linux/amd64` only. The
  payload is architecture-neutral filesystem data, the immediate consumer
  (Antithesis) runs `amd64`, and a single-arch manifest is the cheapest
  shape that satisfies stock Docker daemons. Multi-arch is a follow-up if a
  consumer requirement arises.

### Key Entities

- **Scenario**: a committed JSON document under `examples/scenarios/`
  describing a Cardano testnet, identified to consumers by its short name
  (`local-fast`, `normal`).
- **Scenario digest**: the canonical hash of the scenario JSON, already
  emitted in `metadata.json` by Feature 002. Acts as the content-derived
  part of the primary tag.
- **Baker commit SHA**: the Git SHA of the baker source tree that produced
  the artifact. Used in the secondary tag and recorded in artifact metadata.
- **Seed artifact**: the published, content-addressable bundle whose
  payload is the `/seed/` tree for one scenario at one baker commit.
- **Compose acceptance harness**: the existing
  `compose/acceptance/run.sh` flow, run against the seed extracted from the
  artifact-under-test before publish.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A downstream operator can switch from a hand-baked seed
  directory to the published artifact by changing one identifier in their
  Dockerfile, and no other consumer-side change is required.
- **SC-002**: For an unchanged scenario, two consecutive baker pushes
  produce the same artifact manifest digest. Verified by an automated
  determinism check in the build gate that compares the digests across
  rebuilds.
- **SC-003**: A reviewer can reproduce any published artifact from source
  offline — no registry pulls, no CI runner trust — and the manifest digest
  matches the published one. Verified by the documented offline reproduction
  walkthrough.
- **SC-004**: The build gate fails when compose acceptance fails against
  the extracted seed, and never publishes an artifact for which the
  acceptance harness has not first succeeded.
- **SC-005**: The publishing path adds no more than 3 minutes to the build
  gate beyond the existing synthesis cost (acceptable headroom for the
  per-PR cadence the project already accepts for `normal`).
- **SC-006**: The downstream wiring PR in `lambdasistemi/amaru-bootstrap`
  (its issue #15) lands by reference to this feature's documentation alone,
  with no synchronous design coordination needed.

## Assumptions

- Both committed scenarios (`local-fast`, `normal`) are in scope. Adding
  new committed scenarios in the future automatically extends publishing
  without needing to amend this spec.
- The OCI registry hosting the artifacts is `ghcr.io` under the
  `lambdasistemi` organization. Choice of `ghcr.io` is a project-wide
  default, not a re-decision in this feature.
- The baker's existing scenario digest in `metadata.json` is stable and
  suitable as a content-addressable primary tag fragment. Feature 002 has
  already established this property.
- The Docker Compose acceptance harness from Features 001 and 002 is the
  authoritative startup proof. This feature reuses it; it does not introduce
  a new acceptance contract.
- Consumers are downstream Cardano stacks (today `amaru-bootstrap`,
  tomorrow Antithesis testnet, future internal stacks). Public, third-party
  consumption is out of scope for v1; the registry and naming conventions
  stay friendly to it but no marketing or external announcement is part of
  this feature.
- `lambdasistemi/amaru-bootstrap#15` is the paired downstream wiring PR. It
  is out of scope for this feature; this feature delivers only the artifact
  contract and the documentation that PR consumes.
- The CLI image (`ghcr.io/lambdasistemi/cardano-testnet-baker`, named in
  the constitution's Distribution Targets section) is a *separate* artifact
  and is out of scope here.

## Dependencies

- Feature 002 (ChainDB synthesis MVP, merged via PR #10) provides the
  deterministic `/seed/` payload, the `scenarioDigest`, and the
  `synthesis-report.json` this feature publishes. No further synthesis
  changes are required by this feature.
- The compose acceptance harness shipped with Features 001 and 002 must be
  available as-is.
- Constitution v1.1.0 §II (Determinism), §III (Pinning, never moving tags),
  and §VI (Compose acceptance against generated assets before merge) govern
  this feature.

## Out of Scope

- Publishing the CLI image (separate distribution target).
- Native binary distribution (DEB/RPM/AppImage/Homebrew tap) — already
  tracked elsewhere as a future Distribution Target.
- Public discoverability or marketing of the seed image (no project page,
  no README banner beyond the consumer-pinning instructions).
- The downstream compose-stack wiring PR in `lambdasistemi/amaru-bootstrap`.
  Tracked separately as that repo's issue #15.
- Adding new scenarios. The set of published scenarios is exactly the
  committed `examples/scenarios/` set.
- Changes to synthesis semantics or to the `/seed/` directory layout. This
  feature distributes what Feature 002 produces; it does not redesign it.
