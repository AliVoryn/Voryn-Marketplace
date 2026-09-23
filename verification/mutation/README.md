# Mutation verification

Mutation testing evaluates the strength of the existing test suite by introducing small, deliberate source changes and checking whether the targeted tests detect them. It is a meta-verification layer, not a normal `*.t.sol` test category.

The campaign targets protocol/accounting contracts rather than deployment scripts or vendored dependencies. It is intentionally manual/nightly because mutation campaigns are materially more expensive than ordinary tests.

## Run

```bash
forge install foundry-rs/forge-std@v1.16.2 --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.4.0 --no-commit
forge install smartcontractkit/chainlink-evm@contracts-v1.5.0 --no-commit
./verification/mutation/run.sh
```

Gambit generates mutants under its configured output directory. The generated mutant must then be exercised by the narrowest relevant Foundry suite; a mutant surviving the suite is a test-strength finding that should result in a stronger behavioral/property test.
