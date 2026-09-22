# Ali Voryn Protocol

Production-oriented Solidity/EVM protocol reference implementation built with Foundry.

## Scope

The repository contains a modular protocol suite for Treasury, PaymentManager, Marketplace, Open Auction, Blind Auction, Dutch Auction, Staking, Raffle, NFT issuance, Registry, Factory, and governance primitives.

The repository is organized by protocol domain. Tests remain close to the behavior they specify, while independent execution models such as stateful invariants, forks, and deployment verification have dedicated roots.

## Toolchain

- Foundry v1.8.3
- Solidity 0.8.24
- OpenZeppelin Contracts v5.4.0
- OpenZeppelin Contracts Upgradeable v5.4.0
- Chainlink EVM contracts v1.5.0
- forge-std v1.16.2

## Setup

```bash
cp .env.example .env
make setup
make fmt-check
make build
make test
```

## Verification

```bash
make lint
make coverage
make fuzz
make invariant
make snapshot
```

Run `make preflight` and `make verify-deployment` only with an explicit target RPC and reviewed environment configuration. A mainnet release additionally requires ownership acceptance through the Timelock, factory-controller finalization, live VRF verification, source verification, and post-deployment smoke tests.

On Windows, if the project is under a folder with non-ASCII characters, run Forge through `.orge-ascii.ps1 <command>`. For example: `.orge-ascii.ps1 coverage --report summary --no-match-path 'script/**'`. This avoids a Windows pipe failure in the Solidity compiler while preserving the command's exit code.

## Current verification surface

The repository contains 84 Foundry test files: Unit 12, Integration 10, Fuzz 11, Invariant 11, Security 12, Regression 7, Fork 1, Upgrade 1, Conformance 2, Deployment 1, library suites 9, signed orders 1 and automation 6. The default profile runs 649 tests (648 pass, 1 fork test is skipped without an RPC). Source coverage is 98.04% lines, 96.48% statements, 88.78% branches and 98.46% functions (`docs/coverage-baseline.md`). Mutation and symbolic verification are kept under `verification/` as meta-level tools.

## Testing model

Behavior is tested at multiple levels: example-based tests for deterministic scenarios, fuzz/property tests for variable inputs, stateful invariants for protocol-wide properties, integration tests for multi-contract flows, upgrade tests for UUPS behavior, deployment tests for wiring, regression tests for discovered failures, and fork tests where live external state affects correctness.

Coverage is a diagnostic signal. A test is retained because it specifies a behavior or property, not because it executes an uncovered line.

## Deployment

Deployment scripts are split by responsibility: protocol deployment, ownership handoff, governance setup, VRF subscription setup, deployment preflight, and post-deployment verification. Read `docs/mainnet.md` and `docs/raffle-mainnet.md` before broadcasting.

Never commit `.env`, private keys, RPC credentials, API keys, or production secrets.

## Security

Read `SECURITY.md`. This repository is not an independently audited mainnet release. External security review, operational review, target-chain integration verification, and staged deployment remain release gates.


## Chainlink CRE Automation

Automation is implemented as a separate receiver/workflow layer. Core contracts remain Chainlink-agnostic. See `docs/AUTOMATION.md` and `cre/protocol-automation/README.md` for the deployment flow and the required testnet gate. The workflow needs Node 22 or newer: `make cre-install`, `make cre-typecheck`, `make cre-test`.
