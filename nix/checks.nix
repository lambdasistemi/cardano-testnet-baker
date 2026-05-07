{ project }:

# Flake checks: each is a derivation. Currently only the unit-tests
# suite. Future feature specs add scenario-baking checks here.
let
  flakePkgs = project.flake { };
in
{
  unit-tests =
    flakePkgs.packages."cardano-testnet-baker:test:unit-tests";
}
