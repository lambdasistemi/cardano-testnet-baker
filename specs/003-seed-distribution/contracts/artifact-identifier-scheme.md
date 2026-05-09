# Contract: Artifact Identifier Scheme

**Feature**: [../spec.md](../spec.md)

This contract is what downstream consumers and reviewers pin against.
Once published, the rules below are stable; changing them is a
breaking change to consumers.

## Registry

```
ghcr.io/lambdasistemi/cardano-testnet-seed
```

The path is fixed. Public visibility, pull-by-tag.

## Tag grammar

```ebnf
tag           = primary-tag | secondary-tag ;

primary-tag   = scenario "-" scenario-digest ;
secondary-tag = scenario "-sha-" commit-sha-short ;

scenario         = lowercase-ascii { lowercase-ascii | digit | "-" } ;
scenario-digest  = 64 * hex ;
commit-sha-short = 7  * hex ;

lowercase-ascii  = "a" | … | "z" ;
digit            = "0" | … | "9" ;
hex              = digit | "a" | "b" | "c" | "d" | "e" | "f" ;
```

### Source of `<scenario-digest>`

The 64-hex `scenario-digest` is sourced from
`metadata.json.inputDigest`, which is the SHA-256 of the canonical
scenario JSON. The same 64-hex value also appears in
`synthesis-report.json` as `scenarioDigest` (when the scenario enables
synthesis), so the names diverge between files but the bytes are
identical. The publish app reads `metadata.json.inputDigest` because
metadata is always present and deterministic; the user-visible tag
fragment retains the consumer-friendly `<scenarioDigest>` spelling.

## Tag semantics

| Tag | Resolves to | Stability |
|---|---|---|
| `<scenario>-<scenario-digest>` | manifest digest D₁ | as long as the scenario JSON content yields the same digest, the tag re-resolves to a manifest equivalent in payload (potentially different baker SHA but byte-identical `/seed/`); its manifest digest is byte-identical when the build inputs are unchanged |
| `<scenario>-sha-<commit-sha-short>` | manifest digest D₂ | for one specific baker commit. Even if the scenario JSON later reverts to a content the same hash, this tag will not be reused |

## Forbidden tags

The publish pipeline MUST refuse to push:

- `latest`
- `main`, `master`, `next`, `dev`, `prod`
- any branch name
- any tag that does not include either `<scenario-digest>` or
  `sha-<commit-sha-short>`

Refusal happens at the publish-script layer, before any `skopeo` call.

## Examples (illustrative)

```text
ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-3a9f4d1c8b2e6f7a90c1de4b5f6789abcdef0123456789abcdef0123456789ab2c1
ghcr.io/lambdasistemi/cardano-testnet-seed:local-fast-sha-832deb6
ghcr.io/lambdasistemi/cardano-testnet-seed:normal-sha-832deb6
```

## Pinning guidance for consumers

- **Long-term pin**: use the primary content-derived tag. It survives
  benign baker churn and re-resolves to the same content.
- **Per-commit pin**: use the secondary tag when you specifically need
  to reproduce the artifact a given baker commit produced (audit
  scenarios, post-mortem).
- **Either tag may be promoted to a manifest digest pin** in downstream
  Dockerfiles for the strongest guarantee:
  `…@sha256:<manifest-digest>`.
