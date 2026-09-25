#!/usr/bin/env bash
set -euo pipefail

command -v solc >/dev/null 2>&1 || {
  echo "solc is required for symbolic verification; install Solidity 0.8.24 before running this command." >&2
  exit 1
}

output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT

solc \
  --base-path . \
  --include-path lib \
  --optimize \
  --model-checker-engine all \
  --model-checker-timeout 10000 \
  verification/symbolic/FeeMathHarness.sol \
  verification/symbolic/AuctionMathHarness.sol \
  verification/symbolic/RewardMathHarness.sol 2>&1 | tee "$output_file"

if grep -Eq 'Solver .* is not available|analysis was not possible' "$output_file"; then
  echo "symbolic verification did not run: install a solc-compatible Z3 or CVC4 solver." >&2
  exit 1
fi
