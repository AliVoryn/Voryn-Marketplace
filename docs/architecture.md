# Architecture

The protocol is organized around explicit responsibilities: factory and registry lifecycle, treasury and payment accounting, marketplace and auction execution, staking rewards, NFT custody, and raffle randomness.

## Design rules

- Financial components track assets, claims, and liabilities explicitly.
- External callbacks are authenticated before state transitions.
- Privileged operations are explicit in ownership, roles, and governance.
- Upgradeability is used only where operationally justified.
- Domain behavior is kept close to its tests; independent execution models use dedicated test roots.
- Deployment configuration is explicit and reproducible.

## Trust boundaries

The primary trust boundaries are OpenZeppelin primitives, Chainlink VRF, external token contracts, deployer and governance accounts, and user-controlled receivers. These boundaries are represented directly in implementation and testing.

## Factory deployment architecture

`ProtocolFactory` deploys every protocol contract, but it does not embed their creation code. Contract creation lives in six external libraries (`src/factory/deployers/`), which the Factory calls with `delegatecall`. Because the library code runs in the Factory's context, the creator, the CREATE2 deployer and `msg.sender` seen by each new contract are still the Factory; only the bytecode storage moved. This keeps the Factory runtime below the 24,576-byte EIP-170 limit and its initcode below the EIP-3860 limit. Foundry links the libraries automatically in tests and in `forge script`; each library must also be source-verified.

## Authority over Treasury payer rights

A Treasury payer can move unencumbered Treasury funds (`pay`). The Factory can grant payer rights to contracts it creates, but only when the caller already controls the Treasury: `createStaking` and `createMarketplace` require the caller to be the Treasury owner or pending owner. Other instance types (auctions, raffle, dutch, blind) cannot spend Treasury funds and remain open to any caller. After `finalizeProtocolSuiteControllers` the Factory loses payer-granting rights entirely; from then on only the Treasury owner (the Timelock) can authorize payers.
