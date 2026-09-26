# Preflight Gate

The preflight script is the last automated check between a reviewed commit and a signed transaction. It is
deliberately small, deliberately read-only, and deliberately unforgiving.

```bash
forge script script/Preflight.s.sol --rpc-url "$RPC_URL"          # requires RPC_URL + EXPECTED_CHAIN_ID in the environment
```

which runs:

```bash
forge script script/Preflight.s.sol --rpc-url "$RPC_URL"
```

No broadcast flag, no private key usage, no state change. If preflight fails, nothing is deployed.

---

## 1. What it checks

`PreflightScript.run()` is `view` and performs six checks, each with a distinct error.

| # | Check | Error on failure | Why it matters |
| --- | --- | --- | --- |
| 1 | `block.chainid == EXPECTED_CHAIN_ID` | `WrongChain(expected, actual)` | The single most common deployment accident: broadcasting to the wrong network because `RPC_URL` pointed somewhere else |
| 2 | `DEPLOYER_PRIVATE_KEY != 0` | `ZeroAddress("DEPLOYER")` | Catches an unset or empty key before the broadcast fails midway |
| 3 | `PROTOCOL_ADMIN != address(0)` | `ZeroAddress("PROTOCOL_ADMIN")` | A zero admin would deploy a suite nobody can administer |
| 4 | `FEE_RECIPIENT != address(0)` | `ZeroAddress("FEE_RECIPIENT")` | A zero fee recipient silently sends protocol fees nowhere |
| 5 | `RAFFLE_FEE_BPS <= 1000` (default `250`) | `InvalidFee(feeBps)` | The contract's `MAX_FEE_BPS` is 1000; failing here gives a clearer message than a constructor revert |
| 6 | `3 <= VRF_REQUEST_CONFIRMATIONS <= 200` (default `3`) | `InvalidConfirmationCount(n)` | Matches `Raffle._validateVRFConfig`; catching it here avoids a confusing failure inside a deployment script |

Checks 5 and 6 use `vm.envOr`, so a deployment that does not touch the raffle still passes with defaults.

## 2. What it deliberately does not do

Understanding the boundary is as important as the checks themselves.

| Not checked | Why | Where it is covered instead |
| --- | --- | --- |
| Contract bytecode or size | Requires a build artefact, not an RPC read | `forge build --sizes`, before preflight in the runbook |
| Test suite status | Preflight is an environment gate, not a CI gate | CI / `forge test` before the release branch is cut |
| VRF coordinator address validity | Requires chain-specific Chainlink documentation | Manual verification against official docs — [raffle-mainnet.md](raffle-mainnet.md) step 1 |
| Keystone forwarder address validity | Same reason | Manual verification before receiver deployment |
| Whether `PROTOCOL_ADMIN` is the Timelock | Preflight has no knowledge of the intended governance address | `forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"` check `admin-timelock`, after deployment |
| Explorer / verification configuration | Out of scope for the on-chain gate | `ETHERSCAN_API_KEY` and the verification plan in [mainnet.md](mainnet.md) |
| Whether the deployer holds enough ETH | A broadcast-time concern | Investigate if the broadcast fails |

## 3. Where it sits in the release sequence

```text
reviewed commit on a clean checkout
        |
        v
git submodule update --init --recursive               pinned dependencies installed and verified
        |
        v
forge build --sizes      size gate (EIP-170 / EIP-3860)
        |
        v
forge test                full suite
FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'     extended fuzz profile
FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'    extended invariant profile
forge lint                static analysis
        |
        v
forge script script/Preflight.s.sol --rpc-url "$RPC_URL"           <-- this gate
        |
        v
forge script script/Deploy.s.sol --broadcast
        |
        v
forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"   authority graph re-checked on-chain
        |
        v
post-deployment smoke tests
```

Preflight is the last gate, but it is not the only one: it assumes the earlier gates have already passed on
the same commit.

## 4. Running it safely

```bash
export EXPECTED_CHAIN_ID=11155111        # the chain you intend to deploy to
export RPC_URL=https://…                 # the endpoint for that same chain
export PROTOCOL_ADMIN=0x…                # the Timelock address for a governance release
export FEE_RECIPIENT=0x…
export DEPLOYER_PRIVATE_KEY=0x…          # only read, never used to sign

forge script script/Preflight.s.sol --rpc-url "$RPC_URL"
```

Two operating rules:

1. **Set `EXPECTED_CHAIN_ID` from the deployment plan, not from the RPC endpoint.** Filling it in from the
   chain the RPC happens to be serving defeats the purpose of the check.
2. **Run it on the exact commit being deployed.** A preflight run on a different revision proves nothing
   about the artefact that will be broadcast.

## 5. Failure playbook

| Failure | Most likely cause | Action |
| --- | --- | --- |
| `WrongChain(expected, actual)` | `RPC_URL` points at a different network than intended | Fix `RPC_URL` or fix the expectation — never "adjust the expectation to match" without re-reviewing the plan |
| `ZeroAddress("DEPLOYER")` | `DEPLOYER_PRIVATE_KEY` unset or `.env` not loaded | Load the environment, then re-run |
| `ZeroAddress("PROTOCOL_ADMIN")` | Admin address not set | Set it to the Timelock for a governance release |
| `ZeroAddress("FEE_RECIPIENT")` | Fee recipient not set | Set the reviewed fee recipient address |
| `InvalidFee(n)` | `RAFFLE_FEE_BPS` above the 10% ceiling | Correct the configuration; do not raise the ceiling |
| `InvalidConfirmationCount(n)` | `VRF_REQUEST_CONFIRMATIONS` outside `[3, 200]` | Correct the configuration against the target chain's VRF guidance |

## 6. After preflight passes

Preflight passing means the environment is sane. It does **not** mean the deployment is correct. The
remaining verification is:

1. `forge script script/Deploy.s.sol --broadcast` — record every printed address.
2. Source-verify the seven Factory-related contracts plus every deployed instance.
3. `forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"` with the recorded addresses — this is the authoritative check that the
   authority graph matches the design.
4. Post-deployment smoke tests, one per subsystem ([deployment.md](deployment.md#7-post-deployment-smoke-tests)).

If `forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"` reports a mismatch, treat the deployment as failed: fix the configuration,
redeploy to a fresh address set, and do not patch around it with manual transactions.
