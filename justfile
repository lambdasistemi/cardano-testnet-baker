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
        .#checks.x86_64-linux.cabal-check \
        .#checks.x86_64-linux.haddock \
        .#checks.x86_64-linux.scenario-schema \
        .#checks.x86_64-linux.example-bake-determinism \
        .#checks.x86_64-linux.synthesis-report-shape \
        .#devShells.x86_64-linux.default.inputDerivation

# Validate committed scenario examples against the published schema.
validate-scenarios:
    #!/usr/bin/env bash
    set -euo pipefail
    check-jsonschema \
        --schemafile schemas/scenario/v1.schema.json \
        examples/scenarios/local-fast.json \
        examples/scenarios/normal.json

# Bake the local-fast example into a scratch output directory.
bake-local-fast out="tmp/bakes/local-fast":
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{ out }}"
    nix run . -- bake \
        --scenario examples/scenarios/local-fast.json \
        --out "{{ out }}"

# Synthesize the routine local-fast ChainDB seed.
synthesize-local-fast out="tmp/synthesis/local-fast":
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{ out }}"
    nix run . -- bake \
        --scenario examples/scenarios/local-fast.json \
        --out "{{ out }}"

# Run the realistic normal synthesis measurement path.
measure-normal out="tmp/synthesis/normal":
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{ out }}"
    nix run . -- bake \
        --scenario examples/scenarios/normal.json \
        --out "{{ out }}"
    jq . "{{ out }}/synthesis-report.json"

# Bake both committed scenarios into scratch output directories.
bake-examples out="tmp/bakes":
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{ out }}/local-fast" "{{ out }}/normal"
    mkdir -p "{{ out }}"
    nix run . -- bake \
        --scenario examples/scenarios/local-fast.json \
        --out "{{ out }}/local-fast"
    nix run . -- bake \
        --scenario examples/scenarios/normal.json \
        --out "{{ out }}/normal"

# Reproduce issue #15: bake examples/scenarios/normal.json twice and
# diff the chain-db/volatile/blocks-*.dat file set. RED on the pre-fix
# baker SHA; GREEN once slice 2 of feature 015 lands.
reproduce-15-drift:
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/reproduce-15-drift.sh

# Run compose acceptance for the local-fast example.
acceptance-local-fast out="tmp/bakes/local-fast":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d "{{ out }}" ]]; then
        just bake-local-fast "{{ out }}"
    fi
    compose/acceptance/run.sh local-fast "{{ out }}"

# Run compose acceptance for the normal example.
acceptance-normal out="tmp/bakes/normal":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d "{{ out }}" ]]; then
        rm -rf "{{ out }}"
        nix run . -- bake \
            --scenario examples/scenarios/normal.json \
            --out "{{ out }}"
    fi
    compose/acceptance/run.sh normal "{{ out }}"

# Local mirror of the CI pipeline.
CI:
    #!/usr/bin/env bash
    set -euo pipefail
    just build-gate
    just format-check
    just hlint
    just validate-scenarios
    nix run .#unit-tests --quiet
    rm -rf tmp/ci-acceptance
    just synthesize-local-fast tmp/ci-acceptance/bakes/local-fast
    just acceptance-local-fast tmp/ci-acceptance/bakes/local-fast
