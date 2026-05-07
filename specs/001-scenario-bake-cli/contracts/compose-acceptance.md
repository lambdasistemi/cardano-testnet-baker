# Docker Compose Acceptance Contract

Purpose: prove generated assets are consumable by a real node startup path.

Command shape:

```text
compose/acceptance/run.sh <scenario-name> <baked-output-dir>
```

Image pinning:
- The `cardano-node` service MUST use an immutable image reference. A digest
  pin is preferred. If a local Nix-built acceptance image is used instead, the
  Nix input that produces it MUST be SHA-pinned and recorded in the acceptance
  run logs.

Acceptance steps:
1. Copy `<baked-output-dir>` into a temporary runtime directory.
2. Patch `systemStart` and Byron `startTime` only in the runtime copy.
3. Start the Docker Compose cluster with the baked genesis/config/key material
   mounted read-only.
4. Wait until each configured node either starts far enough to validate initial
   chain state or exits with a validation error.
5. Stop and remove the compose project.

Passing verdict:
- The node process accepts genesis files, node config, operational certificate,
  KES key, VRF key, and pool key material during startup.

Failing verdicts:
- Genesis parse or validation error.
- Node config references a missing or wrong genesis file.
- Operational certificate, KES, VRF, cold, or stake key mismatch.
- Container exits before startup validation completes.
- Timeout before the harness observes a startup acceptance signal.

Non-goals:
- Long-running network convergence.
- ChainDB synthesis.
- Transaction generation.
- Published OCI images for baked artifacts.
