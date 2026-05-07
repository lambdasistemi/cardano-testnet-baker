{ pkgs, project }:

# Flake checks: each is a derivation.
let
  flakePkgs = project.flake { };
  baker = flakePkgs.packages."cardano-testnet-baker:exe:cardano-testnet-baker";
  library =
    flakePkgs.packages."cardano-testnet-baker:lib:cardano-testnet-baker";
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
    nativeBuildInputs = [ baker pkgs.diffutils pkgs.findutils ];
    src = ../.;
  } ''
    bake_and_diff() {
      scenario=$1
      first="$TMPDIR/$scenario-a"
      second="$TMPDIR/$scenario-b"

      cardano-testnet-baker bake \
        --scenario "$src/examples/scenarios/$scenario.json" \
        --out "$first"
      cardano-testnet-baker bake \
        --scenario "$src/examples/scenarios/$scenario.json" \
        --out "$second"

      diff -ru "$first" "$second"
      (cd "$first" && find . -type f -printf '%P %m\n' | sort) > "$TMPDIR/$scenario-a.modes"
      (cd "$second" && find . -type f -printf '%P %m\n' | sort) > "$TMPDIR/$scenario-b.modes"
      diff -u "$TMPDIR/$scenario-a.modes" "$TMPDIR/$scenario-b.modes"
    }

    bake_and_diff local-fast
    bake_and_diff normal
    touch "$out"
  '';
}
