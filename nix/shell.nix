{ pkgs, project }:

# Dev shell: cabal/ghc/fourmolu/hlint come from haskell.nix's project
# shell tools; we augment with shell utilities the orchestrator and
# tests will need.
project.shellFor {
  withHoogle = false;
  tools = {
    cabal = { version = "3.10.3.0"; };
    fourmolu = { version = "0.16.2.0"; };
    hlint = { };
    haskell-language-server = { };
  };
  buildInputs = with pkgs; [
    just
    jq
    nixfmt-classic
    shellcheck
  ];
  exactDeps = true;
}
