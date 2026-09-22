🏪 Voryn Marketplace Protocol

<p>
  <strong>Modular on-chain marketplace infrastructure for NFT trading, auctions, staking, treasury accounting, and protocol deployment.</strong>
</p>

<p>
  Built with Solidity <strong>0.8.24</strong> and OpenZeppelin contracts, with explicit state machines,
  escrowed value flows, signed listings, upgradeable marketplace infrastructure, protocol registries,
  and deployable protocol components.
</p>

<p>
  <a href="https://www.soliditylang.org/"><img src="https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity&logoColor=white" alt="Solidity 0.8.24"></a>
  <a href="https://docs.openzeppelin.com/contracts/5.x/"><img src="https://img.shields.io/badge/OpenZeppelin-Contracts-4E5EE4?logo=openzeppelin&logoColor=white" alt="OpenZeppelin Contracts"></a>
  <a href="https://eips.ethereum.org/EIPS/eip-712"><img src="https://img.shields.io/badge/EIP--712-Signed%20Orders-627EEA?logo=ethereum&logoColor=white" alt="EIP-712"></a>
  <a href="https://docs.openzeppelin.com/contracts/5.x/api/proxy#UUPSUpgradeable"><img src="https://img.shields.io/badge/UUPS-Upgradeable-6E56CF" alt="UUPS Upgradeable"></a>
  <a href="https://docs.openzeppelin.com/contracts/5.x/api/proxy#ERC1967Proxy"><img src="https://img.shields.io/badge/ERC--1967-Proxy-627EEA?logo=ethereum&logoColor=white" alt="ERC-1967"></a>
  <a href="https://remix.ethereum.org/"><img src="https://img.shields.io/badge/Remix-Ready-00B0D8?logo=remix&logoColor=white" alt="Remix"></a>
</p>

</div>

📖 Overview

Voryn Marketplace Protocol is a modular Ethereum smart-contract system for building an on-chain marketplace around NFT assets and related protocol infrastructure.

The system separates trading, auctions, staking, payment accounting, treasury management, governance primitives, deployment, and registry responsibilities into dedicated contracts and libraries.

At its core, the protocol provides:

NFT creation and ownership management

Fixed-price marketplace listings

Escrowed buyer offers

EIP-712 signed listings

Open English-style auctions

Blind commit-reveal auctions

Dutch price-decreasing auctions

Native ETH staking and reward programs

Treasury-backed protocol accounting

Claim-based payment settlement

Protocol instance deployment through a factory

On-chain registration and indexing of deployed instances

Role-based administration and timelock/governance primitives

UUPS-upgradeable marketplace infrastructure

🧩 Protocol Modules

🛒 Marketplace

core/Marketplace.sol

The Marketplace is the main trading layer and is deployed behind an ERC-1967 proxy using the UUPS upgradeability pattern.

Listings

Create listings for supported NFT assets

Update listing price and expiry

Cancel individual listings

Batch-cancel listings

Expire stale listings

Buy active listings with native ETH

Track listing ownership and state

Offers

Make escrowed buyer offers

Cancel offers

Expire offers

Accept offers and settle seller proceeds

Reject offers and return escrowed value

Track buyer offer indexes

Enforce offer lifecycle states

Signed Listings

The marketplace supports off-chain signed listing orders using EIP-712 typed data.

The implementation includes:

Domain separation

Structured order hashing

Per-account nonces

Nonce invalidation

Signature validation

Replay protection

Signature deadline validation

Administration

Marketplace administration includes:

Protocol fee configuration

Minimum fee configuration

Per-account custom fee tiers

Treasury configuration

Payment manager configuration

Pause/unpause controls

Role-gated UUPS upgrade authorization

🔨 Open Auction

core/OpenAuction.sol

A time-based auction module for competitive native-ETH bidding.

Supported behavior includes:

Configurable reserve price

Minimum bid increments

Scheduled auction start

Auction duration

Bid history

Buyout configuration and execution

Auction extension near the deadline

Finalization and settlement

Seller cancellation

Bid refund accounting

Pull-based refund withdrawal

Protocol fee settlement through the treasury

Escrow liability tracking

Escrow invariant checks

Auction timing and bidding calculations are separated into reusable libraries.

🕵️ Blind Auction

core/BlindAuction.sol

A commit-reveal auction module that keeps bid values hidden during the bidding phase.

The lifecycle is divided into:

Bidding
   ↓
Reveal
   ↓
Awaiting Finalization
   ↓
Ended

Supported behavior includes:

Blinded bid commitments

Multiple bids per bidder with bounded bid count

Commit-reveal validation

Fake-bid support

Deposit-based escrow

Highest revealed bid tracking

Reveal-period extensions

Reserve-price validation

Pull-based refunds

Cancellation and cancellation refunds

NFT escrow and release

Seller proceeds and protocol fee settlement

Escrow invariant checks

📉 Dutch Auction

core/DutchAuction.sol

A price-decreasing auction where the asset starts at a configured price and moves linearly toward a lower final price over time.

Supported behavior includes:

Configurable start and end price

Scheduled or immediate activation

Deterministic time-based price calculation

Exact-price purchase execution

NFT escrow

Protocol fee settlement

Seller proceeds settlement through the treasury

Seller or owner cancellation

Expiration and NFT return

Pause/unpause controls

Price calculation uses OpenZeppelin Math.mulDiv for deterministic proportional arithmetic.

🎨 Custom NFT

core/CustomNFT.sol

A protocol-specific NFT contract implementing ownership, balances, approvals, transfers, metadata, and minting controls.

Features include:

Role-based minting

Batch minting with a bounded batch size

Maximum supply

Per-wallet mint limits

Scheduled mint windows

Token-level metadata

Base URI configuration

Standard approval and operator approval flows

Safe transfer receiver checks

Owner token enumeration

Burning

Pause/unpause controls

Roles include:

DEFAULT_ADMIN_ROLE
MINTER_ROLE
OPERATOR_ROLE
METADATA_ROLE

🥩 Staking & Rewards

core/Staking.sol

A native-ETH staking module with scheduled reward programs and explicit user accounting.

Supported flows include:

Stake ETH

Partial unstake

Claim rewards

Compound rewards

Emergency unstake

Configurable minimum and maximum stake bounds

Unstaking cooldowns

Emergency penalties

Reward funding

Treasury-funded reward transfers

Scheduled reward programs

Reward phases

Reward inventory accounting

Global reward-per-token accounting

Reward calculations are isolated in RewardMath.

🏦 Treasury

core/Treasury.sol

The Treasury provides the protocol's controlled ETH accounting and payment boundary.

It separates recorded liabilities from available funds and supports:

Claimable user balances

Authorized protocol payers

Protocol fee configuration

Fee recipient configuration

Controlled outbound payments

Per-payer daily spending limits

Remaining daily allowance tracking

Pull-based claim withdrawals

Available-balance calculation

Emergency rescue of uncommitted ETH

The accounting boundary is conceptually:

Actual ETH balance
        -
Recorded liabilities
        =
Available balance

💰 Payment Manager

core/PaymentManager.sol

A lightweight claim-based payment accounting layer used by protocol components that need to credit and later release ETH to users.

Supported behavior includes:

Authorized creditors

User credit balances

Pull-based withdrawals

Claimable balance tracking

Reentrancy protection

Explicit prevention of unsolicited direct payments

🏭 Protocol Factory

factory/ProtocolFactory.sol

The factory acts as the deployment and composition layer for protocol instances.

It can create:

Treasury instances

Payment Manager instances

Marketplace proxy instances

Custom NFT instances

Deterministic Custom NFT instances

Open Auction instances

Blind Auction instances

Dutch Auction instances

Staking instances

Complete protocol suites

The factory also:

Connects deployed components to their required infrastructure

Authorizes protocol components with treasury/payment contracts

Registers deployed instances

Tracks instances by creator

Supports deterministic NFT deployment using creator-namespaced salts

Predicts deterministic NFT addresses

📚 Protocol Registry

registries/ProtocolRegistry.sol

The registry maintains an on-chain index of deployed protocol instances.

Each instance record contains:

instance
implementation
creator
kind
version
active

Instances can be indexed by:

Global instance set

Protocol kind

Creator

Registrar authorization is separated from registry ownership so protocol deployment can register instances without exposing registry administration broadly.

🔐 Governance & Access

governance/ProtocolGovernance.sol

The protocol includes governance primitives built on OpenZeppelin:

ProtocolAccessManager → AccessManager

ProtocolTimelock → TimelockController

Individual protocol components additionally use:

Ownable2Step

AccessControl

Role-specific permissions

Pause controls

Authorized payer/creditor boundaries

These primitives provide the building blocks for controlled administrative execution and delayed governance actions.

🏗️ Architecture

                              ┌──────────────────────┐
                              │       Protocol User   │
                              └──────────┬───────────┘
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │    Protocol Factory   │
                              └──────────┬───────────┘
                                         │
          ┌──────────────────────────────┼──────────────────────────────┐
          │                              │                              │
          ▼                              ▼                              ▼
   ┌───────────────┐             ┌───────────────┐              ┌──────────────┐
   │  Marketplace  │             │    Auctions   │              │   Staking    │
   └───────┬───────┘             └───────┬───────┘              └──────┬───────┘
           │                             │                             │
           └─────────────────────────────┼─────────────────────────────┘
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │       Treasury       │
                              └──────────┬───────────┘
                                         │
                               ┌─────────┴─────────┐
                               ▼                   ▼
                        Seller/User Claims   Protocol Fees

                  ┌──────────────────────┐
                  │    Payment Manager   │
                  └──────────────────────┘

                  ┌──────────────────────┐
                  │   Protocol Registry  │
                  └──────────────────────┘

                  ┌──────────────────────┐
                  │  Governance Layer    │
                  │ AccessManager /      │
                  │ TimelockController   │
                  └──────────────────────┘

🔄 Core Value Flows

Fixed-Price Sale

Buyer
  │
  │ ETH
  ▼
Marketplace
  │
  ├── protocol fee ──────► Treasury
  │
  └── seller proceeds ───► Treasury claim

Escrowed Offer

Buyer
  │
  │ ETH
  ▼
Marketplace Escrow
  │
  ├── Accepted ───► seller proceeds + protocol fee
  ├── Cancelled ──► buyer claim
  ├── Expired ────► buyer claim
  └── Rejected ───► buyer claim

Auction Settlement

Bid / Purchase
      │
      ▼
Auction Contract
      │
      ├── protocol fee ─────► Treasury
      ├── seller proceeds ───► Treasury
      └── NFT ───────────────► buyer / seller on finalization

🧮 Accounting & State Design

Value-moving modules use explicit state and liability accounting rather than relying solely on contract ETH balances.

Important protocol concepts include:

Listing lifecycle states

Offer lifecycle states

Auction phases and statuses

Staking reward phases

Claimable liabilities

Refund liabilities

Protocol fee splits

Per-payer spending limits

Nonce-based order replay protection

For treasury-backed flows, user or protocol liabilities are accounted for separately from immediately available funds.

📐 Reusable Libraries

Calculation-heavy logic is extracted from stateful contracts into focused libraries.

Library

Responsibility

AccountingMath

Liability-aware available-balance calculations

AuctionMath

Minimum bid and auction extension calculations

AuctionPhaseLib

Blind-auction phase and deadline management

FeeMath

Protocol fee and seller-proceeds splitting

ListingMath

Listing expiry and activity checks

OrderHashLib

EIP-712 listing-order struct hashing

PhaseLogic

Generic deadline/window calculations

RewardMath

Reward-per-token and user reward calculations

This separation keeps financial formulas, timing rules, and protocol state transitions easier to reason about and reuse.

🗂️ Repository Structure

core/
├── BlindAuction.sol
├── CustomNFT.sol
├── DutchAuction.sol
├── Marketplace.sol
├── OpenAuction.sol
├── PaymentManager.sol
├── Staking.sol
└── Treasury.sol

factory/
└── ProtocolFactory.sol

governance/
└── ProtocolGovernance.sol

interfaces/
├── IAuction.sol
├── IBlindAuction.sol
├── ICustomNFT.sol
├── ICustomNFTReceiver.sol
├── IDutchAuction.sol
├── IFactory.sol
├── IMarketplace.sol
├── IPaymentManager.sol
├── IRegistry.sol
├── IStaking.sol
├── ITreasury.sol
└── IUpgradeableSystem.sol

libraries/
├── AccountingMath.sol
├── AuctionMath.sol
├── AuctionPhaseLib.sol
├── FeeMath.sol
├── ListingMath.sol
├── OrderHashLib.sol
├── PhaseLogic.sol
└── RewardMath.sol

proxy/
└── interfaces/
    └── IUpgradeableSystem.sol

registries/
└── ProtocolRegistry.sol

🧰 Technology Stack

Layer

Technology

Smart contracts

Solidity ^0.8.24

Standard library

OpenZeppelin Contracts

Upgradeability

UUPS / ERC-1967

Signed orders

EIP-712 / ECDSA

Access control

Ownable2Step / AccessControl

Governance primitives

AccessManager / TimelockController

Enumeration

EnumerableSet

Arithmetic

OpenZeppelin Math

Development

Remix-compatible project configuration

Settlement asset

Native ETH

🛡️ Security-Oriented Design

The contracts use several defensive patterns throughout the protocol:

Role-based authorization

Two-step ownership transfers where applicable

Reentrancy protection on value-moving operations

Pausable execution paths

Zero-address validation

Explicit lifecycle/state checks

Expiry validation

EIP-712 domain separation

Nonce invalidation and replay protection

Pull-based refund and withdrawal flows

Treasury liability accounting

Per-payer spending limits

Explicit escrow invariants

Seller ownership checks before NFT settlement

Authorized payer and creditor boundaries

These mechanisms are part of the contract design; they are not a substitute for independent testing, formal verification, or security auditing before mainnet use with valuable assets.

🚦 Project Scope

The repository is a smart-contract protocol source tree containing the core contracts, interfaces, reusable libraries, governance wrappers, factory, registry, and proxy interface definitions.

The current source snapshot is intended to represent the protocol implementation itself. Production deployment should be preceded by a complete verification workflow covering compilation, unit tests, integration tests, fuzzing, invariant testing, deployment verification, and independent security review.

Recommended verification flow:

Compile
  ↓
Unit Tests
  ↓
Integration Tests
  ↓
Fuzz Tests
  ↓
Invariant Tests
  ↓
Security Review / Audit
  ↓
Deployment Verification
  ↓
Operational Monitoring

🎯 Design Goals

The protocol is built around a small set of engineering goals:

Explicit State

Listings, offers, auctions, reward programs, and registry entries use explicit state or phase transitions so important lifecycle conditions remain visible in the contract model.

Separation of Concerns

Trading, NFT custody, auctions, staking, treasury accounting, payments, deployment, registry management, and governance are isolated into dedicated components.

Accountable Value Flows

ETH-moving components distinguish user liabilities, protocol fees, seller proceeds, refunds, and available funds so settlement can be reasoned about independently from raw contract balance.

Reusable Logic

Financial arithmetic, deadline logic, reward calculations, and order hashing are extracted into dedicated libraries instead of being duplicated across stateful contracts.

Controlled Administration

Administrative actions are separated through ownership, roles, authorized actors, pause controls, and governance primitives.

<div align="center">

🏪 Voryn Marketplace Protocol

<strong>Composable on-chain commerce infrastructure built around explicit state, modular settlement, and accountable value flows.</strong>

</div>