{ project }:

# Stock IOG executables orchestrated by the baker. These come from the
# pinned ouroboros-consensus source-repository-package in cabal.project.
let
  exes = project.hsPkgs.ouroboros-consensus.components.exes;
in
{
  db-synthesizer = exes.db-synthesizer;
}
