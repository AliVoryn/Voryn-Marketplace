# Test Matrix

The test tree uses one primary navigation axis: the protocol domain or system boundary being verified. A suffix makes a distinct verification model explicit only when it improves cohesion or execution control.

## Current suites

- `Unit`: 12 suite(s)
- `Integration`: 10 suite(s)
- `Fuzz`: 11 suite(s)
- `Invariant`: 11 suite(s)
- `Security`: 12 suite(s)
- `Fork`: 1 suite(s)
- `Regression`: 7 suite(s)
- `Upgrade`: 1 suite(s)
- `Conformance`: 2 suite(s)
- Total suffix-carrying `.t.sol` suites: 67
- Suites without a methodology suffix: `Deployment` 1, library suites 9, signed orders 1, automation 6 (84 `.t.sol` files in total)

## Methodology

- `Unit`: deterministic local behavior, boundaries, reverts, events, and focused accounting.
- `Integration`: multi-contract behavior and protocol boundaries.
- `Fuzz`: variable inputs and explicit arithmetic/accounting/state properties.
- `Invariant`: stateful properties evaluated across action sequences with handlers or actors.
- `Security`: adversarial authorization, callback, reentrancy, griefing, and failure behavior.
- `Fork`: behavior that depends materially on real chain state or external deployment semantics.
- `Regression`: a permanent reproduction of a previously discovered bug.
- `Upgrade`: UUPS initialization, authorization, storage preservation, and proxy behavior.
- `Conformance`: compatibility with an external standard or interface contract.

Not every domain receives every suffix. Missing a suffix is intentional when that verification model adds no meaningful risk coverage.

## Domain tree

```text
auctions/
automation/
factory/
governance/
libraries/
marketplace/
nft/
payment/
protocol/
raffle/
registry/
staking/
support/
treasury/
```

## Automation suites

`test/automation/` verifies the receiver and the discovery layer against the real domain contracts: per-action integration through the receiver, receiver validation branches, bounded discovery and rotation, measured gas against the configured `gasLimit` and `refundBatchSize`, and the deployment scripts. The TypeScript workflow tests live in `cre/protocol-automation/`.

## Verification infrastructure

Mutation and symbolic verification live under `verification/`. They are meta-level tools rather than ordinary domain test suites.

## System-level suites

Deployment and protocol-wide integration remain under `test/protocol/`, while reusable actors, handlers, fixtures, and mocks live under `test/support/`.

## Quality rule

A test exists because it specifies meaningful behavior or a property. Coverage is diagnostic. Weak, duplicated, or coverage-padding tests should be removed or replaced.
