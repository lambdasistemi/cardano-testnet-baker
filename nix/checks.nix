{ pkgs, project, baker, seedImage, scenariosDir, scenarioFiles }:

# Flake checks: each is a derivation.
let
  flakePkgs = project.flake { };
  library =
    flakePkgs.packages."cardano-testnet-baker:lib:cardano-testnet-baker";

  # Two genuinely independent seed-image derivations for the same
  # scenario. `derivationSuffix` flows into the *bakeOut*
  # `runCommand` name, which alters its store path; that store
  # path is captured by `extraCommands` inside `mkSeedImage`, so
  # the resulting `streamLayeredImage` and customisation-layer
  # derivations have distinct hashes and rebuild from scratch.
  #
  # The check oracle is what the seed-distribution contract
  # actually requires (FR-006 + `publish-pipeline.md §"Determinism
  # check"`): the *seed payload* (`layer.tar` bytes) is byte-
  # identical across the pair, AND the image-config fields
  # outside `history` are byte-identical. The two test builds'
  # OCI manifest digests are NOT compared; `dockerTools` embeds
  # the customisation-layer's Nix-store path in
  # `history[].comment`, which differs by construction between
  # genuinely independent builds, so manifest-digest equality
  # cannot hold across the test pair. See the contract for the
  # full rationale.
  #
  # In production, CI runs one build per scenario, the
  # customisation-layer store path is determined by the source
  # code and the flake lock, and the manifest digest pushed to
  # the registry is therefore a pure function of the commit.
  mkSeedImagePair = file: let
    scenarioName = pkgs.lib.removeSuffix ".json" file;
    scenarioPath = scenariosDir + "/${file}";
    mkBuild = suffix: seedImage.mkSeedImage {
      inherit scenarioName scenarioPath;
      derivationSuffix = suffix;
    };
  in {
    inherit scenarioName;
    imageA = mkBuild "-determinism-a";
    imageB = mkBuild "-determinism-b";
  };

  seedImagePairs = map mkSeedImagePair scenarioFiles;

  # Per-scenario fragment of the determinism check shell script.
  # We don't use `skopeo inspect` here because it insists on
  # writing to `/var/tmp` (`creating temporary file: open
  # /var/tmp/container_images_docker-tar...`), which the Nix
  # sandbox doesn't expose.
  #
  # The check verifies determinism at the level that matters
  # for the publish pipeline (FR-006): consumers pulling the
  # registry by tag see a deterministic *layer payload* and
  # deterministic *image-config fields* across rebuilds.
  # Specifically:
  #
  #   1. The image carries one and only one layer; its
  #      compressed `layer.tar` sha256 must match across the
  #      two builds. The layer carries the entire `/seed/`
  #      tree, so this byte-equality is what protects against
  #      host-clock or hostname leaks in the customisation
  #      layer.
  #   2. The image config's *meaningful* fields
  #      (`architecture`, `os`, `created`, `config`,
  #      `rootfs`) must match across the two builds, and the
  #      fixed values (`amd64`, `linux`,
  #      `1970-01-01T00:00:00+00:00`) must hold.
  #
  # We deliberately exclude the `history` field from the
  # config-equality check because `dockerTools.streamLayeredImage`
  # embeds the customisation-layer's Nix-store path in
  # `history[].comment` ("store paths: ['/nix/store/<hash>-…']").
  # Two genuinely independent builds (the reviewer's round-1
  # requirement, addressed by `derivationSuffix`) get distinct
  # store paths there by construction, even though the layer
  # bytes and every consumer-visible field are byte-identical.
  # Comparing `history.comment` would conflate "build-time
  # store-path noise" with real determinism drift.
  determinismCheckScript = pair: ''
    echo "=== ${pair.scenarioName}: comparing two independent builds ==="
    dir_a="$(mktemp -d)"
    dir_b="$(mktemp -d)"
    tar -xzf "${pair.imageA}" -C "$dir_a"
    tar -xzf "${pair.imageB}" -C "$dir_b"

    manifest_a="$dir_a/manifest.json"
    manifest_b="$dir_b/manifest.json"

    # 1. The OCI image must carry exactly one layer (T001's
    #    `mkSeedImage` builds it that way) and the layer.tar
    #    bytes must be byte-identical between the two builds.
    layer_a=$(jq -r '.[0].Layers | if length == 1 then .[0] else "MULTI" end' "$manifest_a")
    layer_b=$(jq -r '.[0].Layers | if length == 1 then .[0] else "MULTI" end' "$manifest_b")
    if [ "$layer_a" = "MULTI" ] || [ "$layer_b" = "MULTI" ]; then
      echo "FAIL: ${pair.scenarioName}: expected exactly one layer per image, got A=$layer_a B=$layer_b"
      exit 1
    fi
    layer_sha_a=$(sha256sum "$dir_a/$layer_a" | awk '{ print $1 }')
    layer_sha_b=$(sha256sum "$dir_b/$layer_b" | awk '{ print $1 }')
    echo "  layer.tar sha256 (A) = $layer_sha_a"
    echo "  layer.tar sha256 (B) = $layer_sha_b"
    if [ "$layer_sha_a" != "$layer_sha_b" ]; then
      echo "FAIL: ${pair.scenarioName}: layer.tar bytes differ between two independent builds (genuine determinism bug)"
      echo "Diagnostic — extracting both layer.tars and listing per-file sha256 mismatches:"
      mkdir -p "$dir_a/extracted" "$dir_b/extracted"
      tar -xf "$dir_a/$layer_a" -C "$dir_a/extracted"
      tar -xf "$dir_b/$layer_b" -C "$dir_b/extracted"
      ( cd "$dir_a/extracted" && find . -type f -printf '%P\n' | sort ) > "$dir_a/files.txt"
      ( cd "$dir_b/extracted" && find . -type f -printf '%P\n' | sort ) > "$dir_b/files.txt"
      if ! diff -q "$dir_a/files.txt" "$dir_b/files.txt" > /dev/null; then
        echo "  file-set differs between A and B:"
        diff -u "$dir_a/files.txt" "$dir_b/files.txt" || true
      fi
      echo "  per-file sha256 differences:"
      while IFS= read -r f; do
        sha_fa=$(sha256sum "$dir_a/extracted/$f" | awk '{ print $1 }')
        sha_fb=
        if [ -f "$dir_b/extracted/$f" ]; then
          sha_fb=$(sha256sum "$dir_b/extracted/$f" | awk '{ print $1 }')
        fi
        if [ "$sha_fa" != "$sha_fb" ]; then
          printf '    %s\n      A=%s\n      B=%s\n' "$f" "$sha_fa" "''${sha_fb:-MISSING}"
        fi
      done < "$dir_a/files.txt"
      exit 1
    fi
    echo "  layer.tar byte-identical — seed payload is deterministic"

    # 2. The image config's meaningful fields must match across
    #    the two builds. We deliberately strip `history` because
    #    dockerTools embeds the customisation-layer's Nix-store
    #    path in `history[].comment`, which differs by
    #    construction when two genuinely independent builds run
    #    in the same derivation. Everything else (architecture,
    #    os, created, config, rootfs.diff_ids) must be
    #    byte-identical.
    config_path_a="$dir_a/$(jq -r '.[0].Config' "$manifest_a")"
    config_path_b="$dir_b/$(jq -r '.[0].Config' "$manifest_b")"
    canonical_a="$dir_a/config-canonical.json"
    canonical_b="$dir_b/config-canonical.json"
    jq -S 'del(.history)' "$config_path_a" > "$canonical_a"
    jq -S 'del(.history)' "$config_path_b" > "$canonical_b"
    if ! diff -u "$canonical_a" "$canonical_b" > /dev/null; then
      echo "FAIL: ${pair.scenarioName}: image config (history-stripped) differs between builds"
      diff -u "$canonical_a" "$canonical_b" || true
      exit 1
    fi
    echo "  image config (history-stripped) byte-identical"

    # 3. Fixed-value invariants the layout contract pins.
    #    Mutating `created`, `architecture`, or `os` in
    #    `nix/seed-image.nix` flips the assertion. (The
    #    archive's config carries `+00:00`; jq normalises both
    #    representations.)
    jq -e '
      .architecture == "amd64" and
      .os == "linux" and
      (.created | startswith("1970-01-01T00:00:00"))
    ' "$config_path_a" > /dev/null
    echo "  fixed-value invariants pass"
    rm -rf "$dir_a" "$dir_b"
  '';
in {
  unit-tests = flakePkgs.packages."cardano-testnet-baker:test:unit-tests";
  haddock = library.haddock;

  cabal-check = pkgs.runCommand "cabal-check" {
    nativeBuildInputs = [ pkgs.cabal-install ];
    src = ../.;
  } ''
    cd "$src"
    cabal check
    touch "$out"
  '';

  scenario-schema = pkgs.runCommand "scenario-schema-validation" {
    nativeBuildInputs = [ pkgs.check-jsonschema ];
    src = ../.;
  } ''
    check-jsonschema \
      --schemafile "$src/schemas/scenario/v1.schema.json" \
      "$src/examples/scenarios/local-fast.json" \
      "$src/examples/scenarios/normal.json"
    touch "$out"
  '';

  example-bake-determinism = pkgs.runCommand "example-bake-determinism" {
    nativeBuildInputs = [ baker pkgs.diffutils pkgs.findutils pkgs.jq ];
    src = ../.;
  } ''
    first="$TMPDIR/local-fast-a"
    second="$TMPDIR/local-fast-b"

    cardano-testnet-baker bake \
      --scenario "$src/examples/scenarios/local-fast.json" \
      --out "$first"
    cardano-testnet-baker bake \
      --scenario "$src/examples/scenarios/local-fast.json" \
      --out "$second"

    test -d "$first/chain-db/immutable"
    test -d "$first/chain-db/ledger"
    test -d "$first/chain-db/volatile"

    diff -ru --exclude synthesis-report.json "$first" "$second"
    jq 'del(.observation)' "$first/synthesis-report.json" > "$TMPDIR/local-fast-a.report"
    jq 'del(.observation)' "$second/synthesis-report.json" > "$TMPDIR/local-fast-b.report"
    diff -u "$TMPDIR/local-fast-a.report" "$TMPDIR/local-fast-b.report"

    (cd "$first" && find . -type f -printf '%P %m\n' | sort) > "$TMPDIR/local-fast-a.modes"
    (cd "$second" && find . -type f -printf '%P %m\n' | sort) > "$TMPDIR/local-fast-b.modes"
    diff -u "$TMPDIR/local-fast-a.modes" "$TMPDIR/local-fast-b.modes"
    touch "$out"
  '';

  synthesis-report-shape = pkgs.runCommand "synthesis-report-shape" {
    nativeBuildInputs = [ baker pkgs.jq ];
    src = ../.;
  } ''
    outdir="$TMPDIR/local-fast"
    cardano-testnet-baker bake \
      --scenario "$src/examples/scenarios/local-fast.json" \
      --out "$outdir"

    jq -e '
      .schemaVersion == 1 and
      .scenarioId == "local-fast" and
      (.scenarioDigest | type == "string" and length == 64) and
      (.bakerVersion | type == "string" and length > 0) and
      .synthesis.slotCount == 720 and
      .synthesis.profile == "local-fast-ci" and
      .chainDb.path == "chain-db" and
      (.chainDb.bytes | type == "number" and . > 1024) and
      (.chainDb.fileCount | type == "number" and . >= 10) and
      (.chainDb.packagedBytes | type == "number") and
      (.chainDb.packagedBytes > .chainDb.bytes) and
      (.observation.wallTimeMilliseconds | type == "number" and . >= 0) and
      (.observation.startedAt | type == "string" and length > 0) and
      (.observation.completedAt | type == "string" and length > 0) and
      (.observation.host | type == "string" and length > 0)
    ' "$outdir/synthesis-report.json" >/dev/null
    touch "$out"
  '';

  seed-image-determinism = pkgs.runCommand "seed-image-determinism" {
    nativeBuildInputs = [ pkgs.coreutils pkgs.gnutar pkgs.jq ];
  } ''
    set -euo pipefail
    cd "$TMPDIR"
    ${pkgs.lib.concatMapStringsSep "\n" determinismCheckScript seedImagePairs}
    touch "$out"
  '';

  # `seed-image-acceptance` is the canonical driver for the
  # build-image-then-run-acceptance flow. It is exposed as a
  # flake check so the GHA `compose-acceptance` job can build
  # it (`nix build .#checks.x86_64-linux.seed-image-acceptance`)
  # and then invoke `result/bin/seed-image-acceptance`, keeping
  # the local-reproduction command and the CI step bit-for-bit
  # identical. The wrapper iterates the same `scenarioFiles`
  # set the rest of the flake enumerates, so adding a new
  # scenario JSON to `examples/scenarios/` immediately extends
  # the acceptance coverage without touching CI yaml.
  #
  # Intentionally NOT added to the Build Gate's `nix build`
  # invocation: the wrapper itself builds with no Docker
  # access, but actually running it requires Docker, so the
  # host must be the `compose-acceptance` runner
  # (`runs-on: ubuntu-latest`), not the Build Gate runner
  # (`runs-on: nixos`).
  seed-image-acceptance =
    let
      scenarioNames = map (f: pkgs.lib.removeSuffix ".json" f) scenarioFiles;
      scenarioListBash = pkgs.lib.concatMapStringsSep " " (n: "'${n}'") scenarioNames;
    in
    pkgs.writeShellApplication {
      name = "seed-image-acceptance";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnutar
        pkgs.jq
        pkgs.skopeo
      ];
      text = ''
        set -euo pipefail
        scenarios=( ${scenarioListBash} )
        if [[ $# -gt 0 ]]; then
          scenarios=( "$@" )
        fi
        for scenario in "''${scenarios[@]}"; do
          echo "=== seed-image-acceptance: $scenario ==="
          out_link="result-seedImage-$scenario"
          nix build ".#seedImage-$scenario" --out-link "$out_link"
          archive=$(readlink -f "$out_link")
          compose/acceptance/run.sh "$scenario" "docker-archive:$archive"
        done
      '';
    };
}
