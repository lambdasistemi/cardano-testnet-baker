{ pkgs }:

# haskell.nix project for the cardano-testnet-baker CLI scaffold.
# Kept deliberately minimal; cardano-* dependencies (CHaP, iohk-nix
# crypto pkgs) will be wired in via a follow-up PR when the first
# feature spec needs them.
pkgs.haskell-nix.cabalProject' {
  name = "cardano-testnet-baker";

  src = pkgs.haskell-nix.haskellLib.cleanSourceWith {
    name = "cardano-testnet-baker-src";
    src = ../.;
    filter = path: _type:
      builtins.match ".*\\.(cabal|hs|project|md)$" path != null
        || builtins.match ".*/src(/.*)?$" path != null
        || builtins.match ".*/app(/.*)?$" path != null
        || builtins.match ".*/test(/.*)?$" path != null
        || builtins.match ".*/cabal\\.project$" path != null
        || builtins.match ".*/LICENSE$" path != null;
  };

  compiler-nix-name = "ghc967";

  shell = {
    withHoogle = false;
    tools = {
      cabal = { version = "3.10.3.0"; };
      fourmolu = { version = "0.16.2.0"; };
      hlint = { };
      haskell-language-server = { };
    };
    buildInputs = with pkgs; [
      just
      nixfmt-classic
      shellcheck
    ];
  };
}
