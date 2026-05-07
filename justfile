# shellcheck shell=bash

set unstable := true

# List available recipes.
default:
    @just --list

# Format Haskell, Cabal, and Nix sources in place.
format:
    #!/usr/bin/env bash
    set -euo pipefail
    for i in {1..3}; do
        fourmolu -i src app test
    done
    cabal-fmt -i *.cabal || true
    nixfmt nix/*.nix flake.nix

# Verify formatting; fails on violations (CI invariant).
format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fourmolu -m check src app test

# Run hlint over the source tree.
hlint:
    #!/usr/bin/env bash
    set -euo pipefail
    hlint src app test

# Build all components via cabal (-O0 for fast dev cycle).
build:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal build all --enable-tests -O0

# Run the unit-tests test suite.
unit match="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ '{{ match }}' == "" ]]; then
        cabal test unit-tests --test-show-details=direct
    else
        cabal test unit-tests \
            --test-show-details=direct \
            --test-option=--match \
            --test-option="{{ match }}"
    fi

# Build everything the CI Build Gate exercises.
build-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    nix build --quiet \
        .#default \
        .#unit-tests \
        .#devShells.x86_64-linux.default.inputDerivation

# Local mirror of the CI pipeline.
CI:
    #!/usr/bin/env bash
    set -euo pipefail
    just build-gate
    just format-check
    just hlint
    nix run .#unit-tests --quiet
