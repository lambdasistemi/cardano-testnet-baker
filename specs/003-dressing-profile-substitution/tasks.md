# Tasks: Haskell Dressing Layer Substituting The Configurator

**Spec**: `spec.md` &nbsp;·&nbsp; **Plan**: `plan.md`

Tasks are ordered.  Each step is a separate commit and leaves the
project in a green CI state.

## T1 — Capture the bash adapter's output as a golden fixture

- [ ] Run `compose/acceptance/multi/adapt.sh` against a deterministic
  bake of `examples/scenarios/antithesis-fast.json` with
  `ACCEPTANCE_START_TIME` pinned to a fixed value.
- [ ] Commit the resulting tree (config.json, *-genesis.json, topology
  per pool, key file metadata) under
  `test/fixtures/dressing/antithesis-configurator/`.

**Why first**: pure-side TDD needs a target.  Pinning the bash output
*before* the rewrite gives the property tests a stable reference.

## T2 — Add `Dressing.Layout`, `Dressing.Patch`, `Dressing.Topology`,
       `Dressing.Runtime`

- [ ] One module per concept under `src/Cardano/Testnet/Baker/Dressing/`.
- [ ] Each module exposes the types in plan.md §"Key Decisions"
  D-2…D-5.
- [ ] Property tests for each (`PatchSpec`, `TopologySpec`,
  `LayoutSpec`, `RuntimeSpec`).
- [ ] No CLI changes; no IO.  All pure.

## T3 — Add `Dressing.Profile` and the `antithesisConfigurator`
       built-in

- [ ] `src/Cardano/Testnet/Baker/Dressing/Profile.hs` defines
  `Profile`, `applyProfile`, `BakedOutput`, `DressedOutput`.
- [ ] `src/Cardano/Testnet/Baker/Dressing/Profiles/AntithesisConfigurator.hs`
  defines `antithesisConfigurator :: Profile`.
- [ ] `ProfileSpec` + `AntithesisConfiguratorSpec`: applying the
  profile to a fixture baked output equals the golden fixture from T1
  (modulo the runtime overrides — pin those with a fixed `Now`).

## T4 — Add `Dress.hs` IO orchestrator and `dress` CLI subcommand

- [ ] `src/Cardano/Testnet/Baker/Dress.hs` implements `dress :: DressOpts -> IO ()`.
- [ ] `src/Cardano/Testnet/Baker/CLI.hs` adds the `dress` subcommand
  with `--scenario`, `--baked`, `--profile`, `--out`,
  `--system-start`.
- [ ] `app/Main.hs` wires the subcommand.
- [ ] Manual end-to-end smoke: `nix run . -- dress` reproduces the
  bash adapter's output on the same inputs.

## T5 — Re-wire the acceptance harness to call `dress`

- [ ] `compose/acceptance/multi/run.sh`: replace the
  `compose/acceptance/multi/adapt.sh` call with
  `nix run . -- dress --scenario … --baked … --profile
  antithesis-configurator --out … --system-start …`.
- [ ] Delete `compose/acceptance/multi/adapt.sh`.
- [ ] Verify `just acceptance-antithesis-master` and
  `just acceptance-antithesis-fast` pass locally.

## T6 — CI workflow update

- [ ] `.github/workflows/ci.yml`: the `Compose acceptance` job
  invokes `dress` instead of the bash adapter.  (If `run.sh` already
  hides that detail, only `cardano-testnet-baker` needs to be
  available in the nix shell, which it already is.)

## T7 — Open PR + loop CI green

- [ ] Open the PR; describe each commit's intent in the PR body.
- [ ] Watch CI via `mcp__pr-checks-guard__wait_for_pr_checks`; fix
  any failures.

## Bisect Invariants

- After T1: project is green; new fixture exists but is unused.
- After T2: project is green; new pure types compile and have green
  unit tests; nothing else uses them yet.
- After T3: project is green; the profile applies cleanly to a
  fixture; CLI still calls bash adapter.
- After T4: project is green; `dress` is available but the
  acceptance harness still calls bash.  Both must agree on output
  (smoke checks this).
- After T5: project is green; the bash adapter is gone and the
  Haskell dress is the only path.
- After T6: CI is green on the rewired path.
