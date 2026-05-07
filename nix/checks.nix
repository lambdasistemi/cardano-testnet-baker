{ pkgs, project, baker }:

# Flake checks: each is a derivation.
let
  flakePkgs = project.flake { };
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

    diff -ru "$first" "$second"
    (cd "$first" && find . -type f -printf '%P %m\n' | sort) > "$TMPDIR/local-fast-a.modes"
    (cd "$second" && find . -type f -printf '%P %m\n' | sort) > "$TMPDIR/local-fast-b.modes"
    diff -u "$TMPDIR/local-fast-a.modes" "$TMPDIR/local-fast-b.modes"
    touch "$out"
  '';
}
