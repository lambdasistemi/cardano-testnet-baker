#!/usr/bin/env bash
set -euo pipefail

.github/scripts/check-action-runtimes.sh

nix develop --quiet -c shellcheck --severity=warning \
    .github/scripts/check-action-runtimes.sh \
    compose/acceptance/patch-system-start.sh \
    compose/acceptance/run.sh

nix develop --quiet -c just CI

git diff --check
