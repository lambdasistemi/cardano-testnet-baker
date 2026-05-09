# Contract: Determinism Harness

**Feature**: [../spec.md](../spec.md)
**Plan**: [../plan.md](../plan.md)

This contract specifies the harness that materialises spec SC-001
("three consecutive CI runs without intermittent failure") and SC-002
("zero file-set differences and zero per-file byte differences across
two independent local builds"). It defines *where* the harness lives,
*what* it asserts, and *how* the three-runs property is composed from
the existing pair-build, the CI cadence, and a new local recipe.

## Surfaces

The harness has three surfaces, each with a distinct responsibility.

### Surface 1 — Existing in-derivation pair-build (`nix/checks.nix:seed-image-determinism`)

**Responsibility**: Detect drift inside one CI invocation by building
each in-scope scenario as two genuinely independent Nix derivations
and diffing the layer payload byte-for-byte.

**Delta in this feature**:

- One-line edit: change
  ```nix
  determinismScenarioFiles = builtins.filter (f: f == "local-fast.json") scenarioFiles;
  ```
  to
  ```nix
  determinismScenarioFiles = scenarioFiles;
  ```
  in `nix/checks.nix` once Phase 0 research has produced a clean
  `seed-image-determinism` run for `normal`.

**Properties asserted** (inherited from PR #12 — this feature does not
modify them):

1. Each scenario's two-pair OCI archives carry exactly one layer.
2. The two `layer.tar` SHA-256s are equal.
3. The two image configs, modulo `history`, are byte-identical
   (`jq 'del(.history)'`).
4. Fixed-value invariants hold: `architecture == "amd64"`,
   `os == "linux"`, `created` begins with `1970-01-01T00:00:00`.

**Failure mode**: prints the per-file SHA-256 mismatch table the PR #12
diagnostic already emits (`b4672c3` commit), then exits non-zero.

### Surface 2 — CI cadence (existing GitHub Actions workflow)

**Responsibility**: Compose three independent observations of
Surface 1 from the existing per-push + per-PR cadence.

**Delta in this feature**: none. The workflow already runs
`seed-image-determinism` on every push and every PR branch (per
003-spec FR-008). After the gate widening in Surface 1, the same
workflow exercises `normal` automatically.

**Reviewer policy** (codified here so the resolve-ticket reviewer can
enforce it): do not approve the merge until at least three consecutive
`seed-image-determinism` runs have completed green on this branch.
Three runs counts both PR pushes and any `recheck` re-invocations of
the same workflow.

### Surface 3 — Local pre-push recipe (`just determinism-normal`)

**Responsibility**: Give the maintainer a fast falsification surface
before pushing.

**Delta in this feature**: add a new `just` recipe to `justfile`:

```just
# Run the seed-image determinism gate three times against the full
# committed scenario set, with --rebuild between calls so each run is
# a fresh derivation. Falsifies intermittent drift before push.
determinism-normal:
    #!/usr/bin/env bash
    set -euo pipefail
    for run in 1 2 3; do
        echo "=== determinism-normal run $run/3 ==="
        nix build --rebuild --quiet \
            .#checks.x86_64-linux.seed-image-determinism
    done
```

**Properties asserted**: the same as Surface 1, three times in a row,
with `--rebuild` so the Nix store cache does not collapse the runs
into one observation.

**Failure mode**: any of the three sub-runs failing fails the recipe;
`set -euo pipefail` ensures the first non-zero exit is the recipe's
exit.

## Composition

The three surfaces compose into the SC-001 / SC-002 properties as
follows:

| Spec property | Surface |
|---------------|---------|
| SC-001: three consecutive CI runs without intermittent failure | Surface 2 + reviewer policy |
| SC-001 (local pre-push): same property exercised before push | Surface 3 |
| SC-002: zero file-set diff, zero per-file byte diff across two independent local builds | Surface 1 (per CI run) |

There is no composite "run all three surfaces from one entry point"
target. The three surfaces are intentionally independent because they
gate different phases of the development loop.

## Out-of-Scope

- Adding a new GitHub Actions matrix that runs the gate three times
  inside one workflow. Rejected: three sequential runs on the same
  runner with the Nix store cached are not three independent
  observations.
- Adding a long-running statistical determinism check (for example,
  100 runs to detect 1%-frequency drift). Rejected as a Feature 015
  scope expansion: SC-001 says "three consecutive CI runs", not "100
  runs".
- Changing the pair-build mechanism in `seed-image-determinism`.
  Rejected per spec Assumption 4 ("the determinism gate built in
  PR #12 is structurally correct; this feature only changes its
  in-scope scenario list, not its pair-build mechanism") and the
  user-memory rule "Don't fix working infra".
