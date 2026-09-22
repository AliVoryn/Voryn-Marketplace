# Test Layout

The test tree has one primary navigation axis: the behavior or system boundary being verified.

A domain directory contains only the verification suites that add real value for that domain. File suffixes make the execution model explicit without creating global `unit`, `fuzz`, `integration`, `security`, or `fork` trees.

Examples:

```text
raffle/
  Raffle.Unit.t.sol
  Raffle.Security.t.sol
  Raffle.Fuzz.t.sol
  Raffle.Invariant.t.sol
  Raffle.Integration.t.sol
  Raffle.Fork.t.sol

staking/
  Staking.Unit.t.sol
  Staking.Security.t.sol
  Staking.Fuzz.t.sol
  Staking.Invariant.t.sol
```

Stateful invariant handlers, actors, and fixtures that belong only to one suite stay close to that suite. Reusable test infrastructure lives under `test/support/`.

Mutation and symbolic verification are meta-level verification tools and remain under `verification/`.

`automation/` verifies the CRE receiver and the bounded discovery views against the real domain contracts; shared wiring for those suites is `support/AutomationIntegrationBase.sol`.
