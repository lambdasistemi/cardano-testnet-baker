---

description: "Task list for Feature 003 — synthesized seed distribution"
---

# Tasks: Synthesized ChainDB Seed Distribution

**Input**: Design documents from `/specs/003-seed-distribution/`
**Prerequisites**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: This feature does not introduce new Haskell code, so it does
not introduce new Haskell-level tests. Acceptance is gated on Nix
checks (`seed-image-determinism`, `seed-image-acceptance`) and on the
existing `compose-acceptance` job, both of which are reused or
extended; we do not duplicate the assertions in this file.

**Branch**: `003-seed-distribution` — already pushed as draft PR #12.

**Vertical-commit discipline**: every task below corresponds to exactly
one bisect-safe commit on this branch. After each commit, the full
build gate (existing checks + any new checks the commit introduces)
must pass. The commit message column gives the exact subject to use.

**Cross-cutting note**: User Stories US1 (consumer pin), US2
(maintainer release), US3 (offline reviewer) all share one
artifact-and-pipeline; they are not independently implementable. Each
implementation task therefore advances all three stories at once. The
[USx] label below names the *primary* story the task unblocks at the
point it lands.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable with peer tasks at the same phase (different
  files, no dependency)
- **[Story]**: primary user story this task unblocks
- All file paths are absolute relative to the repo root

---

## Phase 1: Setup

Already complete. The worktree at
`/code/cardano-testnet-baker-issue-11` is on branch
`003-seed-distribution`, the draft PR is open at
[lambdasistemi/cardano-testnet-baker#12](https://github.com/lambdasistemi/cardano-testnet-baker/pull/12),
the issue [#11](https://github.com/lambdasistemi/cardano-testnet-baker/issues/11)
is on the Planner board with `Category=Antithesis`, `Ownership=Work`.
Spec, plan, research, data-model, contracts, and quickstart are
committed (commits `832deb6`, `566bffa`).

No new Setup tasks.

---

## Phase 2: Foundational — image build + determinism

**Purpose**: produce a deterministic, content-addressable seed image
for every committed scenario. This is the precondition for every later
task. Determinism must be enforced before we dare push, so it lands
inside the Build Gate.

- [ ] **T001** [US2] Add `nix/seed-image.nix` exposing
  `mkSeedImage { scenarioName, scenarioPath }` that:
  1. bakes the scenario via `pkgs.runCommand` (invoking the `baker`
     shell wrapper),
  2. assembles a `/seed/` tree by copying every bake artifact
     byte-for-byte EXCEPT `synthesis-report.json`, which is replaced
     by `jq 'del(.observation)' synthesis-report.json` to match
     Feature 002's existing determinism rule (research §8, contract
     [seed-image-layout.md](./contracts/seed-image-layout.md)),
  3. wraps the assembled tree in
     `pkgs.dockerTools.buildLayeredImage` (NOT `streamLayeredImage`,
     research §1) with
     `created = "1970-01-01T00:00:00Z"`,
     `name = "ghcr.io/lambdasistemi/cardano-testnet-seed"`,
     `architecture = "amd64"`, no entrypoint, no environment.
  Wire `seedImage-<name>` into `flake.nix` `packages.<system>` for
  every file in `examples/scenarios/*.json` (do not hardcode the
  names; iterate the directory).
  - Files: `nix/seed-image.nix` (new), `flake.nix` (extend `packages`).
  - Validates: §I (scenario JSON only), §IV (Nix-first), §V (stock
    `dockerTools` + `jq`), data-model "Seed image", contract
    [seed-image-layout.md](./contracts/seed-image-layout.md), spec
    FR-002.
  - Validation command:
    `nix build -L --out-link result-seedImage-local-fast .#seedImage-local-fast`
    succeeds; the symlink resolves to a *materialized* docker-archive
    tarball.
  - Acceptance:
    `skopeo inspect docker-archive:$(readlink -f result-seedImage-local-fast) | jq '.architecture, .os'`
    yields `"amd64"` and `"linux"`; the layer tar contains
    `seed/synthesis-report.json` whose JSON does NOT include an
    `observation` key (`tar -xOf … seed/synthesis-report.json | jq -e 'has("observation") | not'`);
    tree under `/seed/` matches the layout contract; no manual
    scenario list anywhere in the flake.
  - Commit: `feat(distribution): add seed image flake outputs`.

- [ ] **T002** [US3] Add a `seed-image-determinism` Nix check that, for
  each committed scenario, builds the seed image twice as *genuinely
  independent* derivations (forced via a `derivationSuffix` parameter
  on `mkSeedImage` so the customisation-layer build does not share
  the inner `streamLayeredImage` derivation), then asserts the
  consumer-visible image identity is byte-identical across the pair.
  Skopeo cannot be used inside the Nix sandbox (it insists on
  writing to `/var/tmp` regardless of `$TMPDIR`), so the comparison
  is performed by extracting the docker-archive directly and
  diffing the relevant fields:
  1. **Layer payload**: each archive must carry exactly one layer;
     the two `layer.tar` files must have identical `sha256sum`.
  2. **Meaningful config**: the OCI image config under
     `jq 'del(.history)'` must `diff -u` clean. `history` is
     excluded because `dockerTools.streamLayeredImage` embeds the
     customisation-layer's Nix-store path in `history[].comment`,
     which differs by construction between two genuinely
     independent builds — see contract
     [`publish-pipeline.md §"Determinism check"`](./contracts/publish-pipeline.md)
     for the full rationale and what the consumer-visible identity
     actually is.
  3. **Fixed-value invariants**: `architecture == "amd64"`,
     `os == "linux"`, `created` begins with
     `1970-01-01T00:00:00`.
  Wire into `nix/checks.nix` and add
  `.#checks.x86_64-linux.seed-image-determinism` to the Build Gate
  job's `nix build` invocation in `.github/workflows/ci.yml` (and
  to `just build-gate` for parity).
  - Files: `nix/seed-image.nix` (add `derivationSuffix`),
    `nix/checks.nix` (extend), `flake.nix` (thread `seedImage`,
    `scenariosDir`, `scenarioFiles` to checks),
    `.github/workflows/ci.yml` (extend `build-gate.steps[*].run`),
    `justfile` (extend `build-gate` recipe).
  - Validates: §II (determinism), spec FR-006, contract
    [publish-pipeline.md §"Determinism check"](./contracts/publish-pipeline.md),
    research §1, §8.
  - Validation command:
    `nix build .#checks.x86_64-linux.seed-image-determinism`
    succeeds locally (in CI environment with cachix warm).
  - Acceptance: re-running the check is idempotent; mutating the
    `created` timestamp in `nix/seed-image.nix` (in a throwaway diff)
    flips the fixed-value assertion; reverting the
    `synthesis-report.json` projection step (T001) so the full
    timestamped report enters the image likewise flips the
    layer-payload byte-equality check. Build Gate stays green at
    HEAD.
  - Commit: `feat(distribution): enforce seed image determinism in build gate`.

**Checkpoint**: foundational image produced and determinism enforced.
Nothing publishes yet; nothing is consumer-visible yet.

---

## Phase 3: User Story 2 — maintainer release pipeline (P1)

**Goal**: every push to `main` and every PR branch publishes seed
images for every committed scenario, gated on compose acceptance
against the *image* (not against an unpackaged bake).

**Independent test**: a maintainer pushes a noop commit; CI pushes
two tags per scenario; both tags resolve to the same manifest
digest as the previous push.

- [ ] **T003** [US2] Extend `compose/acceptance/run.sh` to accept
  either a directory path (current behavior) or a
  `docker-archive:<path>` / `oci-archive:<path>` URI. In the archive
  mode, extract `/seed/` into a tmpfs-backed mktemp directory
  (`mktemp -d -p /dev/shm` with a fallback to `$TMPDIR`) using
  `skopeo copy <ref> dir:<tmp>` followed by extraction of the single
  layer tar; cleanup via `trap`. Then invoke the existing startup
  probe against the extracted directory.
  - Files: `compose/acceptance/run.sh` (extend with mode detection),
    `compose/acceptance/lib.sh` (new helper if needed).
  - Validates: spec FR-007, FR-009, contract
    [publish-pipeline.md §"Steps"](./contracts/publish-pipeline.md),
    research §5.
  - Validation commands:
    - `compose/acceptance/run.sh local-fast tmp/bakes/local-fast` (still works)
    - `compose/acceptance/run.sh local-fast docker-archive:./result-seedImage-local-fast` (new)
  - Acceptance: both invocations end with `verdict=accepted`; the
    archive mode leaves no residue in `/dev/shm`; shellcheck clean.
  - Commit: `feat(acceptance): accept oci-archive input alongside directory mode`.

- [ ] **T004** [US2] Add a `seed-image-acceptance` Nix check that
  drives `compose/acceptance/run.sh <scenario>
  docker-archive:<built-archive>` for every committed scenario. The
  check needs Docker; mirror the `compose-acceptance` GHA job's
  `runs-on: ubuntu-latest` constraint by *not* including this check
  in the Build Gate (which runs on `nixos`). Instead, expose it as a
  flake check and invoke it directly from the existing
  `compose-acceptance` GHA job step, replacing the current
  bake-then-run-acceptance with build-image-then-run-acceptance.
  - Files: `nix/checks.nix` (extend),
    `.github/workflows/ci.yml` (modify the `compose-acceptance` job
    to run acceptance against the built image instead of the
    unpackaged bake output).
  - Validates: spec FR-007 ("compose acceptance against the seed
    extracted from the artifact about to be published"), §VI.
  - Validation command: locally
    `nix build .#seedImage-local-fast && compose/acceptance/run.sh
    local-fast docker-archive:$(readlink -f result)`.
  - Acceptance: existing `compose-acceptance` job in CI passes for
    both scenarios with the new image-driven path.
  - Commit: `feat(distribution): run compose acceptance against the seed image`.

- [ ] **T005** [US2] Add `nix/seed-publish.nix` exposing
  `apps.<system>.publishSeedImages`. The app:
  - enumerates `examples/scenarios/*.json`,
  - for each scenario, reads `metadata.json.inputDigest` (the field
    name actually emitted by `src/Cardano/Testnet/Baker/Metadata.hs`
    — see research §4) from the *built* image's
    `/seed/metadata.json`. Extraction path:
    `skopeo copy docker-archive:<built-archive> dir:<tmp> &&
     jq -r '.inputDigest' <tmp>/.../seed/metadata.json` (or untar the
    layer directly). The 64-hex value is the consumer-facing
    `<scenarioDigest>` per
    [contracts/artifact-identifier-scheme.md §"Source of"](./contracts/artifact-identifier-scheme.md),
  - reads the short commit SHA from `git rev-parse --short=7 HEAD`
    (passed in via env var `BAKER_COMMIT_SHA7` for hermeticity in
    derivations),
  - derives both tags per
    [contracts/artifact-identifier-scheme.md](./contracts/artifact-identifier-scheme.md),
  - validates each tag against the forbidden-tag list before any
    push,
  - shells out to `skopeo copy --src-tls-verify --dest-tls-verify
    docker-archive:<built-archive>
    docker://ghcr.io/lambdasistemi/cardano-testnet-seed:<tag>` for
    primary then secondary,
  - supports `--dry-run` (print tags + target URIs, do not invoke
    `skopeo copy`).
  Also add a `just publish-seed-images` recipe wrapping
  `nix run .#publishSeedImages`.
  - Files: `nix/seed-publish.nix` (new), `flake.nix` (extend `apps`),
    `justfile` (add recipe).
  - Validates: spec FR-001, FR-003, FR-004, FR-005, FR-008, contract
    [artifact-identifier-scheme.md](./contracts/artifact-identifier-scheme.md),
    [publish-pipeline.md](./contracts/publish-pipeline.md), research
    §2, §6, §7, §8.
  - Validation command: `nix run .#publishSeedImages -- --dry-run`
    prints exactly four lines (two scenarios × two tags) of the form
    expected by [quickstart.md §A](./quickstart.md).
  - Acceptance: dry-run prints expected tags; calling without
    `--dry-run` against a non-existent registry returns non-zero
    visibly (no silent success); shellcheck clean if any shell is
    used.
  - Commit: `feat(distribution): add publishSeedImages app and just recipe`.

- [ ] **T006** [US2] Add the `seed-image-publish` GHA job to
  `.github/workflows/ci.yml`:
  - `runs-on: nixos`
  - `needs: [build-gate, compose-acceptance]`
  - `permissions: { contents: read, packages: write }` at the job
    level
  - logs into ghcr.io via `${{ github.token }}` for `skopeo`
    (`SKOPEO_AUTH_FILE` populated from `gh auth token`)
  - runs `nix run .#publishSeedImages` with
    `BAKER_COMMIT_SHA7=$(git rev-parse --short=7 HEAD)` exported.
  - Files: `.github/workflows/ci.yml` (new job).
  - Validates: spec FR-008, contract
    [publish-pipeline.md](./contracts/publish-pipeline.md), research
    §3, §6.
  - Validation: `gh run watch` shows the new job appended to the
    workflow; on PR push, the job runs and pushes the four tags;
    `gh api repos/lambdasistemi/cardano-testnet-baker/packages/container/cardano-testnet-seed/versions`
    lists the new tags.
  - Acceptance: tags resolve from a clean machine with only Docker:
    `docker pull
    ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-sha-<short>`
    succeeds; running the consumer Dockerfile snippet from
    [contracts/consumer-copy-from.md](./contracts/consumer-copy-from.md)
    builds clean.
  - Commit: `feat(ci): publish seed images to ghcr on push`.

**Checkpoint US2**: every push publishes both tags for both
scenarios. Maintainers can pin downstream against either tag.

---

## Phase 4: User Story 1 — downstream consumer documentation (P1)

**Goal**: a downstream operator can find, in this repo, exactly the
copy-paste snippet they need to consume a seed.

**Independent test**: a reviewer reading only `README.md` and the
documented `docs/seed-distribution.md` page can write a working
consumer Dockerfile without consulting the spec or the contracts.

- [ ] **T007** [US1] Add `docs/seed-distribution.md` consolidating
  the maintainer / reviewer / consumer flows from
  [quickstart.md](./quickstart.md). Add a "Consuming the seed image"
  section to `README.md` linking the new doc, and refresh the
  README's "Status" section to call Feature 003 landed (with link to
  PR #12 once merged).
  - Files: `docs/seed-distribution.md` (new), `README.md` (extend).
  - Validates: spec FR-010, FR-011, SC-001, SC-006.
  - Validation: rendered preview on GitHub (PR diff view); no broken
    links (`gh-markdown-cli` or manual scan).
  - Acceptance: README Status no longer says Feature 002 is the
    latest; new doc renders with the three flow examples; the
    `amaru-bootstrap` consumer can implement #15 by reading only
    these pages.
  - Commit: `docs: document seed image consumption for downstream stacks`.

**Checkpoint US1**: consumers have copy-pasteable instructions.

---

## Phase 5: User Story 3 — offline reviewer support (P2)

**Goal**: reviewers can independently verify that a published image
matches what source produces.

**Independent test**: clone, check out the published commit, run the
documented commands, observe matching manifest digests against the
registry without trusting it.

US3 is satisfied by the *combination* of Phase 2 and Phase 4, not by
T002 alone:

- T002 (Phase 2) enforces the in-gate determinism oracle: byte-
  identical `layer.tar` payload across genuinely independent test
  builds, and byte-identical image-config fields outside `history`.
  It does *not* directly compare OCI manifest digests across the
  test pair (see FR-006 and
  [contracts/publish-pipeline.md §"Determinism check"](./contracts/publish-pipeline.md)
  for why).
- T006 (Phase 3) is the publish job that materialises a single CI
  build per scenario as a registry manifest. Because the customisation
  layer's store path is fully determined by source + flake lock, two
  CI pushes at the same baker commit publish the same manifest digest.
- T007 (Phase 4) is the documented offline-reproduction walkthrough
  that turns the above two properties into a procedure the reviewer
  follows: rebuild from source, take the local manifest digest, and
  compare it against the registry's digest for the published tag.
  This is where the manifest-digest equality the independent test
  observes actually comes from.

No additional implementation tasks are required for US3.

**Checkpoint US3**: nothing more to do.

---

## Phase 6: Polish — follow-up issues and PR finalisation

- [ ] **T008** [P] Open a follow-up issue in this repo for cosign
  keyless signing of the seed images (referenced from spec FR-013).
  Title: `feat(distribution): sign seed images with cosign keyless`.
  Body: link to FR-013 in this spec, list constitution §III evidence,
  link to Sigstore Fulcio + Rekor docs. Add to the Planner board with
  `Category=Antithesis`, `Ownership=Work`, no Status.
  - Files: none (GitHub action only).
  - Validation: `gh issue view <new#> --repo
    lambdasistemi/cardano-testnet-baker` returns the issue;
    `gh project item-list 2 --owner paolino` lists it.
  - Acceptance: issue exists; spec FR-013 in this repo updated to
    link the new issue (separate doc-only commit).
  - Commit: `docs: link cosign follow-up issue from FR-013` (the
    issue itself is created via `gh issue create`, no commit).

- [ ] **T009** [P] Update PR #12 description to point at the merged
  spec/plan/tasks documents and the implementation commit list.
  Flip the PR from draft to ready-for-review only after all CI
  checks (existing + new) are green.
  - Files: none (PR metadata only).
  - Validation: `gh pr view 12 --repo
    lambdasistemi/cardano-testnet-baker` shows
    `state: OPEN`, `isDraft: false`, all checks
    `conclusion: SUCCESS`.
  - Acceptance: PR view shows updated description; CI green; ready
    for review.
  - Commit: none — PR-metadata change only.

---

## Dependencies & Execution Order

### Phase order

- Phase 2 (T001, T002) is foundational: image must build and be
  proven deterministic before any acceptance or publish work.
- Phase 3 (T003 → T004 → T005 → T006) is sequential: each task
  consumes the prior task's artifact. Cannot parallelise.
- Phase 4 (T007) parallel with anything in Phase 3 once T001 lands
  (the `/seed/` layout is the only input the doc needs).
- Phase 6 (T008, T009) parallelisable with each other and runnable
  any time after Phase 3 completes; T009 must wait for green CI.

### Within Phase 3

```text
T003 (acceptance script) ──┐
                           ├──▶ T004 (Nix check) ──▶ T006 (CI job)
T005 (publish app)  ───────┘
```

T004 depends on T003 because the check shells out to the extended
script. T006 depends on both T004 (acceptance against image) and T005
(the publishSeedImages app it invokes).

### Parallel opportunities

- T007 (docs) is parallel with all of Phase 3 once T001 lands.
- T008 (cosign follow-up issue) is parallel with everything from
  Phase 3 onward.

---

## Implementation Strategy

### MVP

Phase 2 + Phase 3 + T007 deliver an MVP: deterministic image,
acceptance against the image, publish on every push, and
consumer-facing docs.

### Incremental delivery

1. T001 → confirm a flake-output image exists.
2. T002 → confirm the build gate refuses non-deterministic builds.
3. T003 → confirm acceptance still works in directory mode and now
   also in archive mode.
4. T004 → confirm CI runs acceptance against the image.
5. T005 → confirm dry-run produces the expected four-line tag list.
6. T006 → confirm CI pushes; consumer pull from a fresh laptop
   succeeds.
7. T007 → confirm docs render and answer the consumer's question.
8. T008 → record the cosign follow-up so it does not get lost.
9. T009 → request review.

### Cross-cutting constraints (apply to every task)

- After every commit, the full Build Gate must remain green:
  `cabal-check`, `haddock`, `unit-tests`, `scenario-schema`,
  `bake-determinism`, `seed-image-determinism` (added in T002),
  formatting, hlint, compose-acceptance.
- Every task must keep `examples/scenarios/*.json` as the *only*
  scenario source of truth — no scenario name is ever hard-coded
  outside the example files (this includes the workflow YAML).
- Every commit must be signed (`%G?` field == `G` or `U`, not `N`).
- Per memory rule "Always local CI": run `nix develop --quiet -c just
  ci` (or the local-equivalent gate) before each push.
