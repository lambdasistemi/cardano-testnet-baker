## changes-requested

- Finalization is blocked by the current PR CI run:
  <https://github.com/lambdasistemi/cardano-testnet-baker/actions/runs/25581132964/job/75100087121>.
  `Build Gate` failed in `.#checks.x86_64-linux.seed-image-determinism`.
  The check passed `local-fast`, then failed `normal` because the two
  independent seed-image builds produced different layer tar hashes:
  `2d3a6010fa93d89d076a86631cbc33c8c78eee41b231fa4a6e6bbdca10cbabe8`
  versus
  `9abd6972e5c91d720d7b54aa4473b2ffba211501b225701dcf12c0b020f86fa3`.
  That is the determinism gate this PR introduced, so the PR cannot be
  marked ready, approved, or moved to `Done` until the `normal` seed image
  layer is deterministic across independent builds.

No PR metadata finalization or GitHub approval was performed.
