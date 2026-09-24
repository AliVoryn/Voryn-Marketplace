# Local Development

Everything needed to get from a clean checkout to a passing local test run, plus the commands that back
each engineering claim made elsewhere in this documentation set.

---

## 1. Requirements

| Tool | Version | Needed for |
| --- | --- | --- |
| [Foundry](https://getfoundry.sh/) | **v1.8.3** (pinned) | Build, test, fuzz, invariants, coverage, lint, scripts |
| [Git](https://git-scm.com/) | any recent | Dependency install |
| [Node.js](https://nodejs.org/) | **>= 22.6.0** | The CRE TypeScript workspace |
| `RPC_URL` | an archive-capable endpoint | Fork tests, preflight, deployment verification |
| `solc` | 0.8.24 | Only for `verification/symbolic/run.sh` |
| [Gambit](https://github.com/Certora/gambit) | recent | Only for `verification/mutation/run.sh` |

Foundry is pinned for a reason: `forge lint`, `forge fmt`, and the gas and coverage reporting formats used
in this repository differ across releases. Do not "upgrade to latest" while comparing measurements against
[coverage-baseline.md](coverage-baseline.md).

---

## 2. Setup

```bash
git clone https://github.com/AliVoryn/Voryn-Marketplace.git
cd Voryn-Marketplace

cp .env.example .env      # fill in only what you need locally
make setup                # installs pinned Solidity dependencies
```

`make setup` runs `script/install-dependencies.sh`, which installs four dependencies at exact tags and
then **verifies** that four specific files exist:

```text
lib/forge-std/src/Test.sol
lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol
lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol
lib/chainlink-evm/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol
```

If any of them is missing the script exits non-zero, so a partially-installed tree fails loudly instead of
failing later with a confusing import error. An already-populated `lib/<name>` directory is skipped, so the
command is safe to re-run.

### Dependency provenance

| Dependency | Tag |
| --- | --- |
| `foundry-rs/forge-std` | `v1.16.2` |
| `OpenZeppelin/openzeppelin-contracts` | `v5.4.0` |
| `OpenZeppelin/openzeppelin-contracts-upgradeable` | `v5.4.0` |
| `smartcontractkit/chainlink-evm` | `contracts-v1.5.0` |

Import remappings (`remappings.txt`):

```text
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
@chainlink/=lib/chainlink-evm/
forge-std/=lib/forge-std/src/
```

> **Note for a fresh clone.** In the committed tree, `lib/forge-std` is a git submodule pointer and the
> other four `lib/` trees are vendored directly. A clone that does not initialise submodules may need
> `forge install` (which is what `make setup` does) so that `lib/forge-std/src/Test.sol` exists before the
> first build. `.gitattributes` marks `lib/**` as `linguist-vendored`, so vendored code does not distort
> the repository's language statistics.

---

## 3. The daily loop

```bash
make fmt          # rewrite sources in the project style
make fmt-check    # verify formatting (this is what CI gate parity requires)
make build        # forge build --sizes  -> also enforces the EIP-170 size view
make test         # full Foundry suite, -vvv
```

Formatting style is fixed in `foundry.toml`:

```toml
[fmt]
line_length           = 120
bracket_spacing       = true
int_types             = "long"
quote_style           = "double"
multiline_func_header = "attributes_first"
```

`make build` uses `--sizes` on purpose. Contract size is a release gate (EIP-170 runtime ≤ 24,576 bytes,
EIP-3860 initcode ≤ 49,152 bytes), and checking it on every build is cheaper than discovering it during a
deployment.

---

## 4. Test profiles

`foundry.toml` defines three profiles.

| Profile | Fuzz runs | Invariant runs × depth | Verbosity | Use |
| --- | --- | --- | --- | --- |
| `default` | 512 | 128 × 128 | — | Local iteration |
| `ci` | 4096 | 512 × 256 | 3 | CI and pre-merge |
| `ci-fast` | 256 | 64 × 64 | 2 | Quick local sanity pass |

```bash
make fuzz         # FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'
make invariant    # FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'
make coverage     # forge coverage --report summary --no-match-path 'script/**'
make snapshot     # forge snapshot
make lint         # forge lint
make fork         # forge test --match-path 'test/**/*.Fork.t.sol' -vvvv
```

`make fork` requires `RPC_URL`. It runs exactly one suite today — `test/raffle/Raffle.Fork.t.sol` — which
is the only place where real chain state or real external-integration semantics materially affect
correctness.

`FOUNDRY_PROFILE=ci-fast forge test` is the fastest way to know whether a change is structurally sound
before spending CI time on it.

---

## 5. Running one suite

Because the test tree is organised by domain rather than by methodology, targeting a suite is a path
match:

```bash
# One file
forge test --match-path 'test/marketplace/Marketplace.Invariant.t.sol'

# One contract across every methodology
forge test --match-contract Marketplace

# One domain
forge test --match-path 'test/auctions/**'

# One test function
forge test --match-test testFuzz_SignedOrderNonceMonotonic
```

Every suite name in the repository is described in [test-matrix.md](test-matrix.md).

---

## 6. The CRE workspace

The Chainlink CRE workflow is a separate Node package under `cre/protocol-automation/`.

```bash
make cre-install      # npm ci  (lockfile is committed; npm ci fails if it is out of sync)
make cre-typecheck    # tsc -p tsconfig.json
make cre-test         # node --experimental-strip-types --test automation.logic.test.ts config.test.ts
```

Pinned runtime and packages:

| Item | Version |
| --- | --- |
| Node.js | `>= 22.6.0` (declared in `engines`) |
| `@chainlink/cre-sdk` | `1.22.0` |
| `viem` | `2.56.8` |
| `zod` | `3.25.76` |
| `typescript` | `5.9.2` |

The package uses `"type": "module"` and runs tests through Node's native TypeScript stripping
(`--experimental-strip-types`), so there is no separate build step for the tests. The CRE CLI is a distinct
tool: install the version required by the current official Chainlink documentation (1.32.0 at the time of
writing).

`automation.ts` contains the pure decision logic (`runAutomation`, `kindOrder`, `discoveryOffset`) and is
deliberately free of SDK imports so it can be unit-tested without a runtime. `main.ts` is the thin
adaptation layer that binds that logic to the CRE SDK's EVM capability.

---

## 7. Verification tooling

```bash
make mutation     # ./verification/mutation/run.sh  -> requires `gambit`
make symbolic     # ./verification/symbolic/run.sh  -> requires `solc` 0.8.24
```

Both scripts fail fast with an explicit message if their tool is missing, rather than silently skipping:

```text
gambit is required for mutation testing. Install Gambit before running this command.
solc is required for symbolic verification; install Solidity 0.8.24 before running this command.
```

`verification/symbolic/run.sh` invokes `solc --model-checker-engine all --model-checker-timeout 10000` on
three harnesses: `FeeMathHarness.sol`, `AuctionMathHarness.sol`, `RewardMathHarness.sol`.

These are meta-verification layers. They do not replace behavioural tests; see
[test-strategy.md](test-strategy.md).

---

## 8. Deployment commands

```bash
make preflight           # requires RPC_URL; read-only checks before any broadcast
make verify-deployment   # requires RPC_URL; read-only checks of a live deployment
```

Both are read-only and require an explicit, reviewed `RPC_URL`. See [deployment.md](deployment.md) and
[preflight.md](preflight.md). Nothing in the Makefile broadcasts a transaction — broadcasting is always an
explicit `forge script ... --broadcast` invocation performed by an operator.

---

## 9. Full command reference

| Command | Underlying invocation | Requires |
| --- | --- | --- |
| `make setup` | `bash ./script/install-dependencies.sh` | Foundry, git |
| `make fmt` / `make fmt-check` | `forge fmt` / `forge fmt --check` | — |
| `make build` | `forge build --sizes` | — |
| `make test` | `forge test -vvv` | — |
| `make fuzz` | `FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'` | — |
| `make invariant` | `FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'` | — |
| `make coverage` | `forge coverage --report summary --no-match-path 'script/**'` | — |
| `make snapshot` | `forge snapshot` | — |
| `make lint` | `forge lint` | — |
| `make fork` | `forge test --match-path 'test/**/*.Fork.t.sol' -vvvv` | `RPC_URL` |
| `make preflight` | `forge script script/Preflight.s.sol --rpc-url $RPC_URL` | `RPC_URL` |
| `make verify-deployment` | `forge script script/VerifyDeployment.s.sol --rpc-url $RPC_URL` | `RPC_URL` |
| `make mutation` | `./verification/mutation/run.sh` | `gambit` |
| `make symbolic` | `./verification/symbolic/run.sh` | `solc` 0.8.24 |
| `make cre-install` | `cd cre/protocol-automation && npm ci` | Node ≥ 22.6.0 |
| `make cre-typecheck` | `cd cre/protocol-automation && npm run typecheck` | deps installed |
| `make cre-test` | `cd cre/protocol-automation && npm test` | deps installed |
| `make clean` | `forge clean` | — |

---

## 10. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Source "forge-std/Test.sol" not found` | `lib/forge-std` is an uninitialised submodule pointer | `make setup` (or `forge install foundry-rs/forge-std@v1.16.2 --no-git`) |
| `dependency verification failed: … is missing` | A pinned dependency is present but incomplete | Delete the offending `lib/<name>` directory and re-run `make setup` |
| `forge fmt --check` fails on many files | Formatting is the last known-pending engineering task in this repository | Run `make fmt`, then review the diff before committing |
| Fork test fails immediately | `RPC_URL` missing or the endpoint lacks historical state | Set `RPC_URL` to an archive-capable endpoint |
| `gambit is required …` | Mutation tooling not installed | Install Gambit, or skip — it is a manual/nightly layer |
| Coverage numbers differ from the baseline | Different Foundry version or profile | Compare against the recorded profile in [coverage-baseline.md](coverage-baseline.md) |
| `npm ci` fails in the CRE workspace | Lockfile and `package.json` drifted | Fix the drift, or use `npm install` locally and commit the regenerated lockfile |

---

## 11. Environment variables

`.env.example` is the authoritative list. The most important groups:

| Group | Variables |
| --- | --- |
| Core deployment | `RPC_URL`, `DEPLOYER_PRIVATE_KEY`, `PROTOCOL_ADMIN`, `FEE_RECIPIENT`, `EXPECTED_CHAIN_ID` |
| Suite toggles | `DEPLOY_FULL_SUITE`, `DEPLOY_RAFFLE` |
| Known addresses (for verification and follow-up scripts) | `FACTORY_ADDRESS`, `TREASURY_ADDRESS`, `PAYMENT_MANAGER_ADDRESS`, `MARKETPLACE_ADDRESS`, `OPEN_AUCTION_ADDRESS`, `BLIND_AUCTION_ADDRESS`, `DUTCH_AUCTION_ADDRESS`, `STAKING_ADDRESS`, `RAFFLE_ADDRESS`, `REGISTRY_ADDRESS` |
| Chainlink VRF | `VRF_COORDINATOR`, `VRF_SUBSCRIPTION_ID`, `VRF_KEY_HASH`, `VRF_CALLBACK_GAS_LIMIT`, `VRF_REQUEST_CONFIRMATIONS`, `VRF_NATIVE_PAYMENT`, `VRF_LINK_TOKEN`, `VRF_FUNDING_AMOUNT`, `VRF_NATIVE_FUNDING` |
| Governance | `GOVERNANCE_TIMELOCK`, `GOVERNANCE_MIN_DELAY`, `GOVERNANCE_PROPOSER`, `GOVERNANCE_EXECUTOR`, `GOVERNANCE_ADMIN`, `GOVERNANCE_OPERATOR`, `GOVERNANCE_SALT`, `GOVERNANCE_DELAY` |
| Raffle | `RAFFLE_FEE_BPS`, `RAFFLE_OWNER` |
| Automation | `AUTOMATION_ADMIN`, `AUTOMATION_RECEIVER`, `AUTOMATION_OWNER_PRIVATE_KEY`, `CHAINLINK_FORWARDER`, `CHAINLINK_MOCK_FORWARDER`, `CHAIN_SELECTOR`, `PROTOCOL_REGISTRY`, `CRE_WORKFLOW_AUTHOR`, `CRE_WORKFLOW_ID` |
| Source verification | `ETHERSCAN_API_KEY` |

`.gitignore` excludes `.env` and `.env.*` while explicitly allowing `.env.example`. Never remove that
exception, and never commit a populated `.env`.
