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
    iohkNix = {
      # Pinned to the same crypto-overlay revision used by
      # amaru-bootstrap; newer main revisions currently fail the libblst
      # version check during shell construction.
      url = "github:input-output-hk/iohk-nix/fdfc53bc51c684fe086117de651f36572b26655a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    CHaP = {
      url = "github:intersectmbo/cardano-haskell-packages?ref=repo";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      haskellNix,
      iohkNix,
      CHaP,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          inherit (haskellNix) config;
          overlays = [
            iohkNix.overlays.crypto
            haskellNix.overlay
            iohkNix.overlays.haskell-nix-crypto
          ];
        };

        project = import ./nix/project.nix { inherit pkgs CHaP; };
        iogTools = import ./nix/iog-tools.nix { inherit project; };
        flakePkgs = project.flake { };
        baker =
          pkgs.writeShellApplication {
            name = "cardano-testnet-baker";
            runtimeInputs = [
              flakePkgs.packages."cardano-testnet-baker:exe:cardano-testnet-baker"
              iogTools.db-synthesizer
            ];
            text = ''
              exec cardano-testnet-baker "$@"
            '';
          };
        shell = import ./nix/shell.nix { inherit pkgs project iogTools; };
        seedImage = import ./nix/seed-image.nix { inherit pkgs baker; };

        scenariosDir = ./examples/scenarios;
        scenarioFiles = builtins.attrNames (
          pkgs.lib.filterAttrs (
            name: type: type == "regular" && pkgs.lib.hasSuffix ".json" name
          ) (builtins.readDir scenariosDir)
        );
        seedImagePackages = pkgs.lib.listToAttrs (
          map (
            file:
            let
              scenarioName = pkgs.lib.removeSuffix ".json" file;
            in
            {
              name = "seedImage-${scenarioName}";
              value = seedImage.mkSeedImage {
                inherit scenarioName;
                scenarioPath = scenariosDir + "/${file}";
              };
            }
          ) scenarioFiles
        );

        checks = import ./nix/checks.nix {
          inherit
            pkgs
            project
            baker
            seedImage
            scenariosDir
            scenarioFiles
            ;
        };
      in
      {
        packages = flakePkgs.packages // seedImagePackages // {
          default = baker;
          db-synthesizer = iogTools.db-synthesizer;
          unit-tests = flakePkgs.packages."cardano-testnet-baker:test:unit-tests";
        };

        inherit checks;

        devShells.default = shell;

        apps = flakePkgs.apps // {
          default = {
            type = "app";
            program = "${baker}/bin/cardano-testnet-baker";
          };
          db-synthesizer = {
            type = "app";
            program = "${iogTools.db-synthesizer}/bin/db-synthesizer";
          };
        };
      }
    );
}
