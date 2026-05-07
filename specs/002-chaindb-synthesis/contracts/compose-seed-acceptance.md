# Contract: Compose Seed Acceptance

## Invocation

```text
compose/acceptance/run.sh <scenario-name> <baked-output-dir>
```

## Behavior

For synthesis-enabled outputs, the harness must:

1. Copy the baked output into a temporary runtime directory.
2. Patch run-specific startup time in the runtime copy only.
3. Copy `chain-db/` into the node's private writable database directory.
4. Start the pinned cardano-node service with matching genesis, keys, config,
   and database state.
5. Emit `verdict=accepted` only when the node accepts startup from that state.
6. Stop and remove the compose project.

## Failure Conditions

- Missing `chain-db/` for a synthesis-enabled scenario.
- Generated seed, genesis, keys, or config are mismatched.
- Node exits before acceptance.
- Logs show genesis, configuration, key, or ChainDB validation failure.
- The generated output directory is mutated by acceptance.

## Non-Goals

- Multi-producer cluster orchestration.
- Shared mutable ChainDB volumes.
- OCI seed image build or push.
