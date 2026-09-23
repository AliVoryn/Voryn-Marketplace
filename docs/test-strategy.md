# Test Strategy

Testing is layered by behavior and execution model.

## Domain tests

Each protocol subsystem has behavior-focused tests for state transitions, authorization, accounting, events, failures, and boundary conditions.

## Fuzz and property testing

Fuzz tests are used where variable inputs can exercise meaningful properties, especially arithmetic, fees, timestamps, accounting, prices, and signatures.

## Stateful invariants

Handlers model realistic actors and sequences. Critical invariants cover solvency, liability conservation, escrow accounting, reward accounting, and registry consistency.

## Fork testing

Fork tests are reserved for cases where real network state or external integration semantics materially affect correctness. The Chainlink raffle fork smoke test is designed as a release gate and avoids mutating live subscription state.

## Deployment and upgrades

Deployment tests verify dependency wiring and post-deployment behavior. Upgrade tests verify authorization and state preservation for upgradeable contracts.

## Quality rule

Coverage is a diagnostic signal, not the specification. No test should exist only to execute an uncovered line.
