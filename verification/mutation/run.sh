#!/usr/bin/env bash
set -euo pipefail

command -v gambit >/dev/null 2>&1 || {
  echo "gambit is required for mutation testing. Install Gambit before running this command." >&2
  exit 1
}

gambit mutate --json verification/mutation/gambit.json
