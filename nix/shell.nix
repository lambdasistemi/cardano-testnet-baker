{
  pkgs,
  project,
  iogTools,
}:

# Dev shell: cabal/ghc/fourmolu/hlint come from haskell.nix's project
# shell tools; we augment with shell utilities the orchestrator and
# tests will need.
project.shellFor {
  withHoogle = false;
  tools = {
    cabal = { };
    fourmolu = { };
    hlint = { };
    haskell-language-server = { };
  };
  buildInputs =
    with pkgs;
    [
      check-jsonschema
      docker-compose
      just
      jq
      nixfmt-classic
      shellcheck
    ]
    ++ [ iogTools.db-synthesizer ];
  exactDeps = true;
}
