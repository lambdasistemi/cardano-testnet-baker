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
      url = "github:input-output-hk/iohk-nix/9de00113c11ba8cac908a63acf34b193cda7475b";
      inputs.nixpkgs.follows = "nixpkgs";
      # Override transitive `blst` input to fetch via git protocol instead
      # of GitHub's tarball API. GitHub serves different tarball narHashes
      # for the same commit to different clients/over time, which causes
      # spurious `mismatch in field 'narHash'` errors on CI. Git protocol
      # narHashes are derived from the source tree and are stable.
      inputs.blst.url = "git+https://github.com/supranational/blst?ref=v0.3.15&rev=6d960cd05d6fe2b5bc9ba161edf0c1a131b87c4c";
      inputs.blst.flake = false;
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
        checks = import ./nix/checks.nix { inherit pkgs project baker; };
      in
      {
        packages = flakePkgs.packages // {
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
