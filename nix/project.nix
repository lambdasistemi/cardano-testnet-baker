{ pkgs, CHaP }:

# haskell.nix project for the cardano-testnet-baker CLI. CHaP is wired here
# because Feature 001 produces node-accepted Cardano genesis and key material
# using upstream Cardano packages as libraries.
let
  fix-libs = { lib, pkgs, ... }: {
    packages.cardano-crypto-praos.components.library.pkgconfig =
      lib.mkForce [ [ pkgs.libsodium-vrf ] ];
    packages.cardano-crypto-class.components.library.pkgconfig =
      lib.mkForce [[ pkgs.libsodium-vrf pkgs.secp256k1 pkgs.libblst ]];
  };
in pkgs.haskell-nix.cabalProject' {
  name = "cardano-testnet-baker";

  src = pkgs.haskell-nix.haskellLib.cleanSourceWith {
    name = "cardano-testnet-baker-src";
    src = ../.;
    filter = path: _type:
      builtins.match ".*\\.(cabal|hs|project|md)$" path != null
      || builtins.match ".*/src(/.*)?$" path != null
      || builtins.match ".*/app(/.*)?$" path != null
      || builtins.match ".*/test(/.*)?$" path != null
      || builtins.match ".*/examples(/.*)?$" path != null
      || builtins.match ".*/schemas(/.*)?$" path != null
      || builtins.match ".*/cabal\\.project$" path != null
      || builtins.match ".*/LICENSE$" path != null;
  };

  compiler-nix-name = "ghc9123";

  inputMap = { "https://chap.intersectmbo.org/" = CHaP; };

  modules = [ fix-libs ];

  shell = {
    withHoogle = false;
    tools = {
      cabal = { };
      fourmolu = { };
      hlint = { };
      haskell-language-server = { };
    };
    buildInputs = with pkgs; [ just nixfmt-classic shellcheck ];
  };
}
