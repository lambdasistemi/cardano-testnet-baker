{
  pkgs,
  scenariosDir,
  scenarioFiles,
  seedImage,
}:

# `publishSeedImages` is the canonical publish driver. It is exposed
# as a flake `apps.<system>.publishSeedImages` (`nix run
# .#publishSeedImages`) and a `just publish-seed-images` recipe.
#
# Per [contracts/publish-pipeline.md](../specs/003-seed-distribution/contracts/publish-pipeline.md)
# and [contracts/artifact-identifier-scheme.md](../specs/003-seed-distribution/contracts/artifact-identifier-scheme.md),
# the app, for each committed scenario:
#
#   1. Builds the scenario's seed image (`mkSeedImage`).
#   2. Reads `metadata.json.inputDigest` (a 64-hex SHA-256) from
#      the materialised archive's `/seed/metadata.json`. The
#      `inputDigest` field is what `Cardano.Testnet.Baker.Metadata`
#      emits and what the consumer-facing `<scenarioDigest>` tag
#      fragment is sourced from.
#   3. Derives:
#      - primary   = `<scenario>-<scenario-digest>`
#      - secondary = `<scenario>-sha-<commit-sha-short>`
#   4. Validates each tag against the forbidden list (literal
#      moving tags, plus a positive grammar check).
#   5. `skopeo copy --src-tls-verify --dest-tls-verify
#      docker-archive:<archive>
#      docker://ghcr.io/lambdasistemi/cardano-testnet-seed:<tag>`
#      — primary first, then secondary. A primary failure aborts
#      the scenario; a secondary failure is treated as a job-level
#      failure (see contract §"Failure modes").
#
# `BAKER_COMMIT_SHA7` is required (the app refuses to push without
# it). `--dry-run` prints the derived tags + target URIs and exits
# without invoking `skopeo`.
let
  imageRepository = "ghcr.io/lambdasistemi/cardano-testnet-seed";

  scenarioPairs = map (file: {
    scenarioName = pkgs.lib.removeSuffix ".json" file;
    scenarioPath = scenariosDir + "/${file}";
    archive = seedImage.mkSeedImage {
      scenarioName = pkgs.lib.removeSuffix ".json" file;
      scenarioPath = scenariosDir + "/${file}";
    };
  }) scenarioFiles;

  scenarioBashLines = pkgs.lib.concatMapStringsSep "\n" (p: ''
    publish_one '${p.scenarioName}' '${p.archive}'
  '') scenarioPairs;

  publishSeedImages = pkgs.writeShellApplication {
    name = "publishSeedImages";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnutar
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.skopeo
    ];
    text = ''
      set -euo pipefail

      dry_run=false
      for arg in "$@"; do
        case "$arg" in
          --dry-run) dry_run=true ;;
          -h|--help)
            echo "usage: publishSeedImages [--dry-run]" >&2
            echo "  Pushes the seed image for every committed scenario." >&2
            echo "  Requires BAKER_COMMIT_SHA7 (7-hex commit short SHA)." >&2
            echo "  --dry-run prints derived tags + target URIs only." >&2
            exit 0
            ;;
          *)
            echo "unknown argument: $arg" >&2
            exit 2
            ;;
        esac
      done

      commit_sha7=''${BAKER_COMMIT_SHA7:-}
      if [[ -z "$commit_sha7" ]]; then
        echo "BAKER_COMMIT_SHA7 is required (7-hex commit SHA)" >&2
        exit 2
      fi
      if ! [[ "$commit_sha7" =~ ^[0-9a-f]{7}$ ]]; then
        echo "BAKER_COMMIT_SHA7 must be 7 lowercase hex chars; got '$commit_sha7'" >&2
        exit 2
      fi

      forbidden=( latest main master next dev prod )

      validate_tag() {
        local tag=$1
        for bad in "''${forbidden[@]}"; do
          if [[ "$tag" == "$bad" ]]; then
            echo "refusing to push forbidden tag: $tag" >&2
            return 1
          fi
        done
        # Positive check: tag must contain either a 64-hex
        # scenario-digest or `-sha-<7-hex>` per
        # contracts/artifact-identifier-scheme.md.
        if [[ "$tag" =~ -[0-9a-f]{64}$ ]] \
            || [[ "$tag" =~ -sha-[0-9a-f]{7}$ ]]; then
          return 0
        fi
        echo "refusing to push tag without scenario-digest or sha-<short>: $tag" >&2
        return 1
      }

      extract_scenario_digest() {
        local archive=$1
        local tmp
        tmp=$(mktemp -d)
        # shellcheck disable=SC2064
        trap "rm -rf '$tmp'" RETURN
        local seed_root="$tmp/seed-root"
        mkdir -p "$seed_root"
        skopeo copy "docker-archive:$archive" "dir:$tmp/skopeo-dir" >/dev/null
        local manifest="$tmp/skopeo-dir/manifest.json"
        local layer_count
        layer_count=$(jq -r '.layers | length' "$manifest")
        if [[ "$layer_count" != 1 ]]; then
          echo "expected exactly one layer in archive, got $layer_count" >&2
          return 1
        fi
        local layer_digest
        layer_digest=$(jq -r '.layers[0].digest' "$manifest")
        local layer_path="$tmp/skopeo-dir/''${layer_digest#sha256:}"
        tar -xf "$layer_path" -C "$seed_root"
        jq -r '.inputDigest' "$seed_root/seed/metadata.json"
      }

      publish_one() {
        local scenario=$1
        local archive=$2

        local scenario_digest
        scenario_digest=$(extract_scenario_digest "$archive")
        if ! [[ "$scenario_digest" =~ ^[0-9a-f]{64}$ ]]; then
          echo "metadata.inputDigest is not 64-hex: $scenario_digest" >&2
          return 1
        fi

        local primary="$scenario-$scenario_digest"
        local secondary="$scenario-sha-$commit_sha7"
        validate_tag "$primary"
        validate_tag "$secondary"

        local primary_target="${imageRepository}:$primary"
        local secondary_target="${imageRepository}:$secondary"

        if [[ "$dry_run" == true ]]; then
          # Acceptance output path per
          # specs/003-seed-distribution/quickstart.md §A:
          # exactly one `<scenario>  <target-uri>` line per
          # tag, no headers or labels. Two scenarios × two
          # tags = four lines on stdout.
          printf '%s  %s\n' "$scenario" "$primary_target"
          printf '%s  %s\n' "$scenario" "$secondary_target"
          return 0
        fi

        echo "=== $scenario ===" >&2
        printf '  primary   = %s\n' "$primary_target" >&2
        printf '  secondary = %s\n' "$secondary_target" >&2

        skopeo copy \
          --src-tls-verify \
          --dest-tls-verify \
          "docker-archive:$archive" \
          "docker://$primary_target"

        skopeo copy \
          --src-tls-verify \
          --dest-tls-verify \
          "docker-archive:$archive" \
          "docker://$secondary_target"
      }

      ${scenarioBashLines}
    '';
  };
in
{
  inherit publishSeedImages;
}
