{
  description = "Deterministic Cardano testnet artifact baker";

  nixConfig = {
    extra-substituters = [
      "https://cache.iog.io"
      "https://paolino.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "paolino.cachix.org-1:m/ddECNNFmjffrlmCFf3PPoffp46zU0wgoyz1Bj7Wjg="
    ];
  };

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:hamishmack/flake-utils/hkm/nested-hydraJobs";
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , flake-utils
    , haskellNix
    , ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          inherit (haskellNix) config;
          overlays = [ haskellNix.overlay ];
        };

        project = import ./nix/project.nix { inherit pkgs; };
        shell = import ./nix/shell.nix { inherit pkgs project; };
        checks = import ./nix/checks.nix { inherit project; };

        flakePkgs = project.flake { };
      in
      {
        packages = flakePkgs.packages // {
          default =
            flakePkgs.packages."cardano-testnet-baker:exe:cardano-testnet-baker";
          unit-tests =
            flakePkgs.packages."cardano-testnet-baker:test:unit-tests";
        };

        inherit checks;

        devShells.default = shell;

        apps = flakePkgs.apps // {
          default =
            flakePkgs.apps."cardano-testnet-baker:exe:cardano-testnet-baker";
        };
      });
}
