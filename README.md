# cardano-testnet-baker

Deterministic Cardano testnet artifact baker.

Reads a declarative scenario JSON describing the network (initial stake,
producers, faucets, era schedule, optional ChainDB synthesis) and produces a
versioned, reproducible artifact set: genesis files, pool keys, faucet keys,
and an optional synthesized ChainDB seed.

Status: scaffolding in flight. See open PRs.
