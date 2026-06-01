#!/usr/bin/env bash
# Gated end-to-end check: does the committed pi-nvim-bridge bundle connect when
# loaded by the real oh-my-pi (`omp`) binary? Mirrors the manual pi verification
# but is re-runnable by CI/contributors.
#
# Skipped unless RUN_OMP_INTEGRATION=1 (omp must be installed and authenticated).
#
#   RUN_OMP_INTEGRATION=1 tests/support/omp_integration.sh
#
# Override the binary with PI_PANEL_OMP_CMD (e.g. an absolute path).
set -euo pipefail

if [[ "${RUN_OMP_INTEGRATION:-}" != "1" ]]; then
  echo "omp integration check skipped (set RUN_OMP_INTEGRATION=1 to run)"
  exit 0
fi

cd "$(dirname "$0")/../.."
exec nvim --headless -l tests/support/omp_connect.lua
