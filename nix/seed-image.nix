{ pkgs, baker }:

# Builds a deterministic OCI seed image for a single committed scenario.
#
# `mkSeedImage` materialises one docker-archive per scenario:
#
#   1. invokes the baker via `pkgs.runCommand`,
#   2. uses `extraCommands` to assemble `/seed/` directly inside the
#      customisation layer: every bake artifact is copied
#      byte-for-byte except `synthesis-report.json`, which is
#      replaced by `jq 'del(.observation)' synthesis-report.json` so
#      host-dependent timestamps and hostnames cannot leak into the
#      image's manifest digest (see Feature 003 research §8 and
#      Feature 002's `example-bake-determinism` precedent),
#   3. wraps the assembled tree in `pkgs.dockerTools.buildLayeredImage`
#      so the result symlink resolves to a materialised tarball and
#      every downstream tool (skopeo, the determinism check) reads
#      the same bytes (see Feature 003 research §1).
#
# Using `extraCommands` (rather than `contents = [ seedTree ]`) keeps
# the customisation layer free of Nix-store symlinks: `/seed/<x>`
# entries are real files at the image's filesystem root, not
# indirections into a `/nix/store/...-seed-tree/seed/...` path. The
# OCI artifact carries exactly what the layout contract describes.
let
  imageName = "ghcr.io/lambdasistemi/cardano-testnet-seed";

  # `derivationSuffix` lets a caller (in particular the
  # `seed-image-determinism` check) ask for two genuinely
  # independent builds of the same scenario. The suffix is
  # appended to the *bakeOut* derivation name, which percolates
  # through to the `streamLayeredImage` derivation hash (because
  # `extraCommands` captures `${bakeOut}` and that store path
  # changes), so each call below produces a distinct
  # customisation-layer build. The OCI image's `name`, `tag`,
  # `created`, `architecture`, and `config` are unchanged. The
  # `layer.tar` payload is also byte-identical across the pair
  # (the customisation-layer's content is fully determined by
  # the bakeOut content, which is deterministic across renamed
  # bakeOut derivations) — that's the property the
  # `seed-image-determinism` check relies on as its oracle for
  # host-clock / hostname leaks. The OCI config differs only in
  # `history[].comment`, which embeds the customisation-layer's
  # Nix-store path; the check excludes that field per
  # contract `publish-pipeline.md §"Determinism check"`.
  mkSeedImage =
    {
      scenarioName,
      scenarioPath,
      derivationSuffix ? "",
    }:
    let
      bakeOut =
        pkgs.runCommand "${scenarioName}-bake${derivationSuffix}"
          {
            nativeBuildInputs = [ baker ];
          }
          ''
            cardano-testnet-baker bake \
              --scenario ${scenarioPath} \
              --out "$out"
          '';
    in
    pkgs.dockerTools.buildLayeredImage {
      name = imageName;
      tag = scenarioName;
      created = "1970-01-01T00:00:00Z";
      architecture = "amd64";
      contents = [ ];
      extraCommands = ''
        mkdir -p seed
        ${pkgs.coreutils}/bin/cp -r --no-preserve=mode,ownership \
          ${bakeOut}/. seed/
        ${pkgs.coreutils}/bin/chmod -R u+w seed
        ${pkgs.jq}/bin/jq 'del(.observation)' \
          ${bakeOut}/synthesis-report.json \
          > seed/synthesis-report.json
        ${pkgs.findutils}/bin/find seed -type d \
          -exec ${pkgs.coreutils}/bin/chmod 755 {} +
        ${pkgs.findutils}/bin/find seed -type f \
          -exec ${pkgs.coreutils}/bin/chmod 644 {} +
      '';
      config = { };
    };
in
{
  inherit mkSeedImage;
}
