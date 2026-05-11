# antithesis-configurator dressing fixture

Golden snapshot of the bash adapter's output for issue #23.  Used by
`Dressing.ProfileSpec` to assert that the Haskell `applyProfile`
function reproduces the same JSON shape as `adapt.sh` did.

## Reproduction

```sh
nix run --quiet . -- bake \
  --scenario examples/scenarios/antithesis-fast.json \
  --out tmp/fixture-bake

ACCEPTANCE_START_TIME=1735689600 \
  compose/acceptance/multi/adapt.sh tmp/fixture-bake tmp/fixture-dress

for p in p1 p2 p3; do
  cp tmp/fixture-dress/$p/configs/*.json \
     test/fixtures/dressing/antithesis-configurator/$p/configs/
done
```

`1735689600` is `2025-01-01T00:00:00Z`, divisible by the
configurator's 120 s alignment.  Holding the time fixed eliminates
the only non-deterministic field (`systemStart` / `startTime`).

## Contents

- `p1/`, `p2/`, `p3/` per-pool runtime config directories
  (`config.json`, `topology.json`, four genesis files each).
- Keys, `utxo-keys/`, and the bash adapter's internal `.shared/`
  staging dir are deliberately **not** committed: keys are
  byte-identical to baker output (covered by Layout tests) and
  `.shared/` is not part of the dressed-output contract.

## Refresh policy

Refresh only when the dressed contract intentionally changes — for
example when a new patch is added to the antithesis profile.  Drift
between the bash adapter and this fixture is caught by
`AntithesisConfiguratorSpec` during the migration window.
