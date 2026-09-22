<div align="center">

Ali Voryn Protocol

A modular Solidity / EVM protocol built around marketplaces, auctions, staking, raffles, treasury accounting, governance, and Chainlink-powered automation.

<picture>
  <img src="assets/voryn-protocol.gif" alt="Ali Voryn Protocol animated engineering banner" width="900" />
</picture>

<br />








Engineering · Verification · Automation · EVM

</div>

Overview

Ali Voryn Protocol is a production-oriented Solidity/EVM reference implementation designed as a modular protocol suite, not a single-purpose contract.

The codebase brings together:

NFT issuance and ERC-721 behavior

Primary marketplace listings and offers

Open, blind commit-reveal, and Dutch auctions

Treasury and payment accounting

Staking and reward distribution

Chainlink VRF-backed raffles

Factory-based protocol composition and deterministic deployment paths

Registry and protocol governance primitives

Upgradeable marketplace infrastructure

Chainlink CRE automation with bounded discovery and a fail-closed receiver layer

Stateful invariants, fuzzing, security, integration, fork, regression, upgrade, conformance, mutation, and symbolic verification

Reproducible deployment and post-deployment verification workflows

Security status: this repository is a production-oriented engineering reference implementation. It is not presented as an independently audited mainnet release. External security review, target-chain integration validation, operational review, and staged deployment remain release gates.

Protocol Architecture

flowchart TB
    G[ProtocolTimelock / Governance]
    F[ProtocolFactory]
    R[ProtocolRegistry]

    T[Treasury]
    PM[PaymentManager]
    M[Upgradeable Marketplace]
    OA[Open Auction]
    BA[Blind Auction]
    DA[Dutch Auction]
    S[Staking]
    N[CustomNFT]
    RA[Raffle]

    CR[Chainlink CRE Workflow]
    AR[ProtocolAutomationReceiver]
    VRF[Chainlink VRF V2.5]

    G --> F
    G --> M
    G --> T
    G --> PM
    G --> OA
    G --> BA
    G --> DA
    G --> S
    G --> RA
    G --> R

    F --> R
    F --> T
    F --> PM
    F --> M
    F --> OA
    F --> BA
    F --> DA
    F --> S
    F --> N
    F --> RA

    M --> T
    M --> PM
    OA --> T
    BA --> T
    DA --> T
    S --> T
    RA --> T

    VRF --> RA
    CR --> AR
    AR --> OA
    AR --> BA
    AR --> DA
    AR --> M
    AR --> RA
    R --> AR

The architecture intentionally separates protocol domains, shared accounting, deployment/registration, governance, and external automation. Core contracts do not need to know about the CRE workflow layer; automation discovers eligible work through bounded on-chain views and submits validated reports through the receiver.

Core Features

🛒 Marketplace

Listings with creation, update, cancellation, and expiry flows

Direct purchases with escrow-aware settlement

Offers with accept, reject, cancel, and expiry paths

Signed listing execution using EIP-712 typed data

Seller nonces for replay protection

Protocol, minimum, and account-specific fee configuration

Treasury and PaymentManager integration

UUPS upgradeability with role-gated authorization

Pausing and operator controls

Bounded automation discovery for expiring offers

🔨 Open Auction

Reserve prices and minimum bid increments

Scheduled start and explicit lifecycle phases

Bid history and buyout support

Seller/owner cancellation with refund accounting

Pull-based refunds

Escrow solvency invariant

Automation discovery for auctions that require lifecycle finalization

🕵️ Blind Auction

Commit-reveal bidding

Commitment hashing with value/fake/secret parameters

One-time commitment enforcement to reduce replay/front-run opportunities

Reveal extensions

Unrevealed-deposit accounting

Pending-return accounting

Seller proceeds and fee settlement

Cancellation recovery path

Explicit phase model and automation readiness

Escrow invariant tracking

📉 Dutch Auction

Time-decaying price model

Purchases at or above the current price

Current-price calculation from the auction schedule

Excess-payment refunding

Explicit cancellation and expiry flows

Automation discovery for expired auctions

🎟️ Raffle + Chainlink VRF

Ticket purchasing with entrant accounting

Chainlink VRF V2.5 random-winner flow

Native or LINK payment configuration

Request binding and callback validation

Retry path for stuck randomness requests

Controlled stuck-raffle cancellation

Batched refund processing

Failed-raffle finalization

Creator/buyer refund claims

Bounded automation candidate discovery

Fork coverage for external VRF integration

🪙 Staking

Reward funding from the contract or treasury

Scheduled reward programs

Time-bounded reward phases

Stake / unstake flows with accounting boundaries

Claimable rewards

Reward compounding

Cooldown handling

Emergency unstake path

Configurable minimum/maximum stake bounds

Configurable emergency penalty

Reward inventory tracking

Stateful reward/accounting invariants

🖼️ Custom NFT

ERC-721-compatible token behavior

Single and batch minting

Wallet mint limits

Time-windowed mint phases

Burn support

Token URI and base URI management

Role-based minting and metadata administration

Safe transfer handling through IERC721Receiver

ERC-165 / ERC-721 / ERC-721 Metadata conformance

Pause controls and operator authorization

🏦 Treasury

Authorized payer model

Claimable balances

Fee-recipient accounting

Spending windows and daily limits

Remaining allowance tracking

Protocol liabilities / available-balance accounting

Emergency rescue path

Pull-based claim withdrawals

💳 Payment Manager

Authorized creditor model

Credit accounting by reason

Claimable balances

Pull-based withdrawals

Factory-controller lifecycle

Reentrancy protection

🏭 Protocol Factory

Modular deployment of the protocol suite

Dedicated deployer libraries for core components

Protocol-wide creation flow

Custom NFT deployment and deterministic address prediction paths

Auction, staking, raffle, marketplace, treasury, and payment-manager instantiation

Registry registration

Creator instance indexing

Ownership/controller finalization

Treasury-authority checks around dependent deployments

📚 Registry

Instance registration and validation

Registrar authorization

Active/inactive lifecycle

Global, per-kind, and per-creator indexing

Automation-specific instance discovery

Cycle-aware bounded enumeration for off-chain workflows

🏛️ Governance

OpenZeppelin TimelockController based protocol control plane

Two-step ownership handoff patterns across critical contracts

Governance-aware factory finalization

Explicit separation between bootstrap authority and long-term protocol authority

Scripts for scheduling and executing governance ownership acceptance

Chainlink CRE Automation

The automation layer is designed as a separate execution boundary around the protocol.

Cron Trigger
     ↓
CRE Workflow
     ↓
Bounded On-chain Discovery
     ↓
Validated Action Report
     ↓
KeystoneForwarder
     ↓
ProtocolAutomationReceiver
     ↓
Protocol Domain Function

Automated protocol actions

Domain

Automated action

Open Auction

finalizeAuction(uint256)

Blind Auction

finalizeAuction()

Dutch Auction

expireAuction(uint256)

Marketplace

expireOffer(uint256)

Raffle

requestRandomWinner(uint256)

Raffle

processRaffleRefunds(uint256,uint256)

Raffle

finalizeFailedRaffle(uint256)

The receiver layer is intentionally fail-closed. The repository adds explicit action allowlisting, workflow identity validation, target-kind validation, replay/staleness protection, refund-cursor protection, and schedule/value validation. Simulation uses a dedicated receiver so real workflow metadata requirements are not weakened for production.

The workflow also uses bounded discovery rather than unbounded per-ID reads. The repository's automation documentation fixes the execution model to one selected protocol instance per kind per run and documents the read-budget, rotation, partitioning, and gas-budget model.

Official Chainlink CRE documentation: https://docs.chain.link/cre

Verification Strategy

Verification is intentionally layered. A test exists to specify a behavior or property—not merely to increase coverage.

Foundry test model

Layer

Purpose

Unit

Deterministic contract behavior

Integration

Multi-contract protocol flows

Fuzz

Input-space exploration and edge cases

Invariant

Stateful protocol properties and accounting conservation

Security

Access control, replay, reentrancy, lifecycle, and failure-path checks

Regression

Previously identified failures remain fixed

Fork

Live external protocol behavior and target-chain assumptions

Upgrade

Upgradeability and implementation transitions

Conformance

ERC/interface behavior

Deployment

Wiring and deployed-system assumptions

The final engineering review in this repository records 79 *.t.sol suites, 581 test functions, and 14 invariant functions, for 595 combined verification entry points.

Meta-level verification

verification/
├── mutation/
│   ├── gambit.json
│   └── run.sh
└── symbolic/
    ├── AuctionMathHarness.sol
    ├── FeeMathHarness.sol
    ├── RewardMathHarness.sol
    └── run.sh

Mutation testing evaluates whether tests detect controlled source changes.

Symbolic harnesses target high-value arithmetic and monotonicity properties through Solidity's SMT tooling.

Neither layer replaces behavioral, fuzz, invariant, integration, fork, deployment, or security testing.

Repository Structure

.
├── .github/
│   └── workflows/                 # CI + manual fork smoke workflow
├── src/
│   ├── core/                      # Marketplace, auctions, raffle, staking, treasury, NFT, etc.
│   ├── automation/                # Chainlink automation receiver boundary
│   ├── automation/chainlink/      # Receiver template + interfaces
│   ├── factory/                   # Protocol factory + dedicated deployers
│   ├── governance/                # Timelock governance primitive
│   ├── interfaces/                # Protocol interfaces
│   ├── libraries/                 # Shared math, phases, fees, hashes, scanning
│   ├── proxy/                     # Upgrade-related interfaces
│   └── registries/                # Protocol registry
├── test/                          # Domain-first verification tree
│   ├── auctions/
│   ├── automation/
│   ├── factory/
│   ├── governance/
│   ├── libraries/
│   ├── marketplace/
│   ├── nft/
│   ├── payment/
│   ├── protocol/
│   ├── raffle/
│   ├── registry/
│   ├── staking/
│   ├── support/
│   └── treasury/
├── cre/
│   └── protocol-automation/       # Chainlink CRE TypeScript workflow
├── verification/                  # Mutation + symbolic verification
├── script/                        # Deployment, governance, VRF, automation, verification
├── docs/                          # Architecture, test strategy, automation, mainnet runbooks
├── foundry.toml                   # Foundry configuration
├── remappings.txt                 # Dependency import mapping
├── Makefile                       # Reproducible developer commands
├── SECURITY.md                    # Security reporting policy
└── LICENSE                        # MIT

Toolchain & Dependency Pins

The project uses explicit versions to make builds reproducible.

Solidity / Foundry

Component

Version

Solidity

0.8.24

Foundry baseline

1.8.3

forge-std

v1.16.2

OpenZeppelin Contracts

v5.4.0

OpenZeppelin Contracts Upgradeable

v5.4.0

Chainlink EVM

contracts-v1.5.0

Chainlink CRE workspace

Component

Version

Node.js

>=22.6.0

@chainlink/cre-sdk

1.22.0

viem

2.37.6

zod

3.25.76

TypeScript

5.9.2

The repository contains script/install-dependencies.sh to install the pinned Foundry dependencies. The project intentionally keeps dependency installation reproducible rather than relying on moving development branches.

Getting Started

Requirements

Foundry

Node.js >=22.6.0 for the CRE workspace

Git

A configured RPC endpoint for fork/deployment workflows

Install

cp .env.example .env
make setup

Format, build, test

make fmt-check
make build
make test

Deeper verification

make lint
make fuzz
make invariant
make coverage
make snapshot

Fork tests

make fork

Preflight and deployment verification

make preflight
make verify-deployment

These commands require an explicit and reviewed RPC_URL plus the environment expected by the deployment scripts. Do not broadcast transactions from an unreviewed environment.

CRE workflow

cd cre/protocol-automation
npm install
npm test
npm run typecheck

For simulation and deployment sequencing, read cre/protocol-automation/README.md and docs/AUTOMATION.md first.

Deployment Model

Deployment is split by responsibility rather than hiding everything inside one script.

Protocol deployment
        ↓
Registry / protocol registration
        ↓
Governance deployment
        ↓
VRF subscription setup
        ↓
Ownership transfer scheduling
        ↓
Timelock ownership acceptance
        ↓
Factory-controller finalization
        ↓
Deployment verification
        ↓
Post-deployment smoke tests

Available script responsibilities include:

Protocol deployment

Governance deployment

VRF subscription creation and funding

VRF consumer registration

Automation receiver deployment and configuration

Ownership transfer and Timelock acceptance

Protocol finalization

Preflight checks

Deployment verification

Mainnet operational procedure is documented in docs/mainnet.md and docs/raffle-mainnet.md.

CI / Repository Quality

GitHub Actions covers the main engineering gates in .github/workflows/ci.yml:

Format
  ↓
Lint
  ↓
Build + contract sizes
  ↓
Full Foundry test suite
  ↓
Coverage
  ↓
Gas snapshot
  ↓
Static analysis (Slither)

A separate manual workflow provides the Chainlink Raffle fork smoke test using repository secrets for the target RPC and deployment configuration.

Dependabot is configured for dependency update visibility.

Engineering Decisions

Domain-first tests

Tests are organized around the system or protocol boundary under verification. Methodology appears in the filename (.Unit.t.sol, .Fuzz.t.sol, .Invariant.t.sol, etc.) rather than becoming the primary directory hierarchy.

Invariants as protocol properties

The repository checks properties such as escrow solvency, accounting conservation, registry consistency, creator/index consistency, and state-machine correctness across mutable state.

Bounded automation discovery

Automation discovery surfaces explicitly cap both the scan window and the number of returned actions, allowing off-chain workflows to reason about gas and RPC budgets without iterating through unbounded protocol state.

Governance as an actual control plane

The Timelock is treated as a control plane only where ownership/roles actually point at it. The deployment runbook therefore includes explicit ownership acceptance and factory-controller finalization instead of assuming that a deployed Timelock automatically controls the protocol.

Security Notes

The repository includes a dedicated security policy in SECURITY.md.

Do not commit:

.env
private keys
RPC credentials
API keys
production secrets

The repository also distinguishes between:

Passing tests
     ≠
External security audit
     ≠
Target-chain integration verification
     ≠
Operational readiness

Before a real mainnet broadcast, the repository's documented release process requires clean-checkout verification, exact dependency installation, build/size gates, tests, fuzzing/invariants, static analysis, mutation and symbolic checks, target-chain fork validation where applicable, source verification, governance handoff verification, VRF consumer registration, and post-deployment smoke tests.

Known Release Considerations

The current repository documentation explicitly calls out several operational boundaries that should be resolved before a production deployment:

After finalizeProtocolSuiteControllers, the Factory can no longer authorize new Treasury payers. The per-NFT createBlindAuctionInstance flow therefore needs a reviewed authorization strategy for a finalized protocol Treasury.

Marketplace offer refunds through cancelOffer / expireOffer are blocked while the Marketplace is paused.

The repository's release documentation requires a final forge fmt pass before the strict formatting CI gate can be considered clean.

A passing local test suite does not substitute for independent review of live Chainlink configuration, target-chain addresses, or production operations.

Documentation Map

Document

Purpose

docs/architecture.md

System boundaries and protocol architecture

docs/test-strategy.md

Verification philosophy and methodology

docs/test-matrix.md

Domain-by-domain test coverage map

docs/AUTOMATION.md

Solidity automation boundary and execution model

cre/protocol-automation/README.md

CRE workflow architecture and deployment sequence

docs/mainnet.md

Mainnet deployment and governance runbook

docs/raffle-mainnet.md

Chainlink VRF mainnet operations

verification/README.md

Mutation and symbolic verification layers

SECURITY.md

Security reporting policy

DEPENDENCIES.md

Dependency provenance and version pins

RELEASE_FILES.md

Release inventory

RELEASE_MANIFEST.md

Release manifest

FINAL_REVIEW.md

Engineering review scope and verification boundaries

CHANGES.md

Refactor, hardening, and verification changes

Official Technology References

Solidity — https://docs.soliditylang.org/

Foundry — https://getfoundry.sh/

Chainlink — https://docs.chain.link/

Chainlink CRE — https://docs.chain.link/cre

OpenZeppelin Contracts — https://docs.openzeppelin.com/contracts/5.x/

GitHub repository README guidance — https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes

License

This project is released under the MIT License. See LICENSE for details.

<div align="center">

Ali Voryn

Beyond Every Defined Horizon.

Built to explore where protocol architecture, verification, and automation meet.

</div>
