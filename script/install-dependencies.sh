#!/usr/bin/env bash
set -euo pipefail

install_dependency() {
  local spec="$1"
  local dir="$2"
  if [ -d "lib/${dir}" ] && [ -n "$(ls -A "lib/${dir}" 2>/dev/null)" ]; then
    echo "lib/${dir} already present, skipping ${spec}"
    return 0
  fi
  forge install "${spec}" --no-git
}

install_dependency foundry-rs/forge-std@v1.16.2 forge-std
install_dependency OpenZeppelin/openzeppelin-contracts@v5.4.0 openzeppelin-contracts
install_dependency OpenZeppelin/openzeppelin-contracts-upgradeable@v5.4.0 openzeppelin-contracts-upgradeable
install_dependency smartcontractkit/chainlink-evm@contracts-v1.5.0 chainlink-evm

for required in \
  lib/forge-std/src/Test.sol \
  lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol \
  lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol \
  lib/chainlink-evm/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol; do
  if [ ! -f "${required}" ]; then
    echo "dependency verification failed: ${required} is missing" >&2
    exit 1
  fi
done
echo "dependencies installed and verified"
