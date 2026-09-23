#!/usr/bin/env bash
set -euo pipefail

command -v solc >/dev/null 2>&1 || {
  echo "solc is required for symbolic verification; install Solidity 0.8.24 before running this command." >&2
  exit 1
}

solc \
  --base-path . \
  --include-path lib \
  --optimize \
  --model-checker-engine all \
  --model-checker-timeout 10000 \
  verification/symbolic/FeeMathHarness.sol \
  verification/symbolic/AuctionMathHarness.sol \
  verification/symbolic/RewardMathHarness.sol
