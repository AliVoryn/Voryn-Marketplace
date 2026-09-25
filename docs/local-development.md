# Local development

This project uses Foundry directly. Commands in this guide are the same commands run by CI.

## Requirements

- Foundry `v1.8.3`
- Git
- Node.js `>=22.6.0` for `cre/protocol-automation`
- An archive-capable `RPC_URL` only for fork tests and deployment checks
- `solc 0.8.24` and a compatible Z3 or CVC4 library only for the optional symbolic checks
- Gambit only for the optional mutation checks

## Set up a fresh clone

```bash
git clone --recurse-submodules <repository-url>
cd Voryn-Marketplace
cp .env.example .env
```

If the repository was cloned without submodules, initialize `forge-std` explicitly:

```bash
git submodule update --init --recursive
```

`forge-std` is pinned by its Git submodule commit. OpenZeppelin Contracts `v5.4.0`, OpenZeppelin
Contracts Upgradeable `v5.4.0`, and Chainlink EVM `contracts-v1.5.0` are vendored under `lib/`.
Import paths are defined in `remappings.txt`.

## Everyday commands

```bash
forge fmt
forge fmt --check
forge build --sizes
forge lint
forge test
```

The `--sizes` build reports EIP-170 runtime and EIP-3860 initcode margins. Treat an over-limit contract
as a build failure.

## Test profiles

| Profile | Fuzz runs | Invariant runs × depth | Intended use |
| --- | ---: | ---: | --- |
| `default` | 512 | 128 × 128 | Normal local development |
| `ci-fast` | 256 | 64 × 64 | Quick full-suite check |
| `ci` | 4096 | 512 × 256 | Extended fuzz and invariant gates |

```bash
FOUNDRY_PROFILE=ci-fast forge test
FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'
FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'
forge coverage --report summary --no-match-path 'script/**'
forge snapshot
```

Useful filters:

```bash
forge test --match-path 'test/marketplace/Marketplace.Unit.t.sol'
forge test --match-contract Marketplace
forge test --match-path 'test/auctions/**'
forge test --match-test testFuzz_SignedOrderNonceMonotonic
```

The only fork suite currently requires `RPC_URL`:

```bash
forge test --match-path 'test/**/*.Fork.t.sol' -vvvv
```

## CRE automation workspace

The Chainlink CRE workflow is an independent Node package:

```bash
cd cre/protocol-automation
npm ci
npm test
npm run typecheck
```

The package lock is authoritative. Do not use `npm install` in CI or commit an updated lockfile without
reviewing the dependency changes.

## Deployment checks

Preflight and verification are read-only unless `--broadcast` is explicitly supplied:

```bash
forge script script/Preflight.s.sol --rpc-url "$RPC_URL"
forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"
```

Deployment scripts read configuration from the environment. Start from `.env.example`, review every
address and chain identifier, and never put a private key in version control. See [deployment.md](deployment.md)
and [preflight.md](preflight.md) for the release sequence.

## Optional verification

```bash
./verification/mutation/run.sh
./verification/symbolic/run.sh
```

These tools are manual security layers, not substitutes for the Foundry test suite.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `forge-std/Test.sol` cannot be resolved | Run `git submodule update --init --recursive`. |
| Formatting fails on many files | Run `forge fmt`, review the result, then rerun `forge fmt --check`. |
| The fork test fails immediately | Set `RPC_URL` to an archive-capable endpoint. |
| `npm ci` reports lockfile drift | Regenerate intentionally with `npm install`, review, and commit both package files. |
| Coverage differs from the documented baseline | Use Foundry `v1.8.3` and the profile named in [coverage-baseline.md](coverage-baseline.md). |

## CI

`.github/workflows/ci.yml` checks formatting, compilation and contract sizes, lint, the default test
suite, extended fuzz tests, extended invariant tests, and the CRE package's tests and type checking.
Fork, mutation, symbolic, and deployment checks remain explicit because they require external services or
specialized tools.
