{ pkgs, project }:

# Flake checks: each is a derivation.
let flakePkgs = project.flake { };
in {
  unit-tests = flakePkgs.packages."cardano-testnet-baker:test:unit-tests";

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
}
