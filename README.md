🏪 Voryn Marketplace Protocol

<p>
  <strong>A modular Ethereum marketplace protocol for NFT trading, auctions, staking, treasury management, and protocol deployment.</strong>
</p>

<p>
  Built with Solidity <strong>0.8.24</strong> and OpenZeppelin contracts, with upgradeable marketplace infrastructure,
  explicit accounting flows, access control, escrowed offers, signed listings, and protocol registries.
</p>

<p>
  <img src="https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity&logoColor=white" alt="Solidity 0.8.24">
  <img src="https://img.shields.io/badge/OpenZeppelin-5.6.1-4E5EE4?logo=openzeppelin&logoColor=white" alt="OpenZeppelin 5.6.1">
  <img src="https://img.shields.io/badge/Pattern-UUPS%20Upgradeable-6E56CF" alt="UUPS Upgradeable">
  <img src="https://img.shields.io/badge/Protocol-ERC--1967%20Proxy-627EEA?logo=ethereum&logoColor=white" alt="ERC-1967 Proxy">
  <img src="https://img.shields.io/badge/Tooling-Remix-00B0D8?logo=remix&logoColor=white" alt="Remix">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License">
</p>

</div>

📖 Overview

Voryn Marketplace is a modular smart-contract system designed around an on-chain marketplace and its supporting protocol infrastructure.

The repository contains contracts for:

NFT creation and ownership management

Fixed-price listings

Escrowed offers

Signed listings using EIP-712

Open auctions with bidding, buyout, refunds, and settlement

ETH staking and reward programs

Treasury accounting and controlled protocol spending

Payment claims and withdrawals

Protocol instance deployment through a factory

Instance registration and lifecycle tracking

Access-control and timelock primitives

Upgradeable marketplace infrastructure using UUPS and ERC-1967 proxies

The system is organized around explicit state transitions, role-based permissions, escrowed value, protocol fee accounting, and reusable libraries.

🧩 Protocol Components

🛒 Marketplace

core/Marketplace.sol

The Marketplace contract provides the main trading layer.

Supported flows include:

Create, update, cancel, and expire listings

Buy active listings with native ETH

Create and escrow buyer offers

Cancel, expire, reject, or accept offers

Settle seller proceeds and protocol fees through the treasury

Execute signed listings using EIP-712 typed data

Per-account order nonces and nonce invalidation

Custom fee configuration

Batch listing cancellation

Pause and unpause operations

UUPS upgrade authorization

The marketplace uses:

UUPSUpgradeable
ERC1967Proxy
EIP712Upgradeable
AccessControlUpgradeable
PausableUpgradeable
ReentrancyGuard

🎨 Custom NFT

core/CustomNFT.sol

A custom NFT asset contract implementing ownership, balances, approvals, operator approvals, token metadata, minting, burning, and receiver checks without directly inheriting OpenZeppelin's ERC721 implementation.

Capabilities include:

Role-based minting

Batch minting with a maximum batch size

Maximum supply

Per-wallet mint limits

Scheduled mint windows

Token-level metadata

Base URI management

Transfers

Safe transfers through ICustomNFTReceiver

Token enumeration per owner

Burning

Pause and unpause

Roles include:

DEFAULT_ADMIN_ROLE
MINTER_ROLE
OPERATOR_ROLE
METADATA_ROLE

🔨 Open Auction

core/OpenAuction.sol

The auction module supports time-based open auctions using native ETH.

Capabilities include:

Auction creation

Scheduled auction start

Minimum reserve price

Minimum bid increment

Bid history

Buyout configuration

Buyout execution

Auction ending and finalization

Seller cancellation

Refund accounting

Pull-based refund withdrawal

Protocol fee settlement

Escrow invariant checks

Pause and unpause

Auction timing and bid calculations are separated into AuctionMath.

🥩 Staking & Rewards

core/Staking.sol

The staking module provides native ETH staking with scheduled reward programs.

Capabilities include:

ETH staking

Partial unstaking

Reward claiming

Reward compounding

Emergency unstaking

Reward funding

Treasury-funded rewards

Scheduled reward programs

Reward phases

Minimum and maximum stake bounds

Unstaking cooldowns

Emergency penalties

Reward inventory accounting

Global reward-per-token accounting

Pause and unpause

Reward calculations are isolated in RewardMath.

🏦 Treasury

core/Treasury.sol

The Treasury provides controlled protocol-level ETH accounting and payment settlement.

Capabilities include:

Crediting claimable balances

Authorized payer controls

Protocol fee configuration

Fee recipient configuration

Controlled outbound payments

Per-payer daily spending limits

Claimable withdrawals

Available-balance accounting

Emergency rescue of uncommitted funds

The treasury explicitly tracks:

actual ETH balance
        vs.
recorded liabilities

and exposes availableBalance() for the amount that is not reserved by claimable liabilities.

💰 Payment Manager

core/PaymentManager.sol

A separate claim-based payment accounting layer for ETH balances attributable to users.

Capabilities include:

Authorized creditors

Credit accumulation

Claimable balance tracking

Pull-based withdrawals

Total claimable accounting

Reentrancy protection

This component is used by marketplace flows such as offer cancellation, expiration, and rejection.

🏭 Protocol Factory

factories/ProtocolFactory.sol

The factory creates and registers protocol instances.

Supported deployments include:

Treasury

Payment Manager

Marketplace

Custom NFT

Deterministic Custom NFT

Open Auction

Staking

Full protocol suites

The factory also:

Tracks instances by creator

Namespaces deterministic NFT salts by creator

Predicts deterministic NFT addresses

Connects newly created protocol components

Registers instances with the protocol registry

📚 Protocol Registry

registries/ProtocolRegistry.sol

The registry maintains an on-chain index of deployed protocol instances.

Each record contains:

instance
implementation
creator
kind
version
active

Instances can also be queried by:

Kind

Creator

Global instance set

The registry uses OpenZeppelin EnumerableSet for indexed instance collections and supports registrar-based write authorization.

🔐 Governance & Access

access/ProtocolGovernance.sol

The repository includes thin protocol-specific wrappers around:

OpenZeppelin AccessManager

OpenZeppelin TimelockController

These contracts provide governance primitives for controlled administration and delayed execution.

The protocol's individual modules additionally use:

Ownable2Step

AccessControl

Role-specific permissions

Pause controls

Authorized payer / creditor lists

🧱 Architecture

                         ┌──────────────────────┐
                         │      Protocol User   │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │     ProtocolFactory  │
                         └──────────┬───────────┘
                                    │
                ┌───────────────────┼────────────────────┐
                │                   │                    │
                ▼                   ▼                    ▼
          Marketplace          Custom NFT          Open Auction
                │
                ├───────────────┐
                │               │
                ▼               ▼
           Treasury       PaymentManager
                │
                ▼
            Fee / Claim
            Accounting

                    ┌───────────────────────┐
                    │    ProtocolRegistry   │
                    └───────────────────────┘
                              ▲
                              │
                       deployed instances

                    ┌───────────────────────┐
                    │   Governance Layer    │
                    │ AccessManager /       │
                    │ TimelockController    │
                    └───────────────────────┘

🧮 Accounting Model

Financial flows are deliberately separated across protocol components.

Marketplace Settlement

Buyer
  │
  │ ETH
  ▼
Marketplace
  │
  ├── protocol fee ──────► Treasury
  │
  └── seller proceeds ───► Treasury claim

Offer Escrow

Buyer
  │
  │ ETH
  ▼
Marketplace escrow
  │
  ├── Accepted ───► seller proceeds + protocol fee
  ├── Cancelled ──► buyer claim
  ├── Expired ────► buyer claim
  └── Rejected ───► buyer claim

Treasury Solvency Boundary

The treasury distinguishes between:

actual contract balance
        -
total recorded liabilities
        =
available balance

This separation is central to controlled withdrawals, spending limits, and emergency rescue operations.

📐 Reusable Libraries

The project separates calculation and state-transition helpers from core contract logic.

Library

Responsibility

AccountingMath

Available balance and liability-aware accounting

AuctionMath

Minimum bid calculations and auction extension logic

FeeMath

Protocol fee and seller-proceeds calculations

ListingMath

Listing fee and expiry calculations

OrderHashLib

EIP-712 listing order struct hashing

PhaseLogic

Generic time-window and phase calculations

RewardMath

Reward-per-token and staking reward calculations

This keeps financial and timing formulas reusable and easier to reason about independently from stateful contract code.

🗂️ Repository Structure

access/
└── ProtocolGovernance.sol

core/
├── CustomNFT.sol
├── Marketplace.sol
├── OpenAuction.sol
├── PaymentManager.sol
├── Staking.sol
└── Treasury.sol

factories/
└── ProtocolFactory.sol

registries/
└── ProtocolRegistry.sol

interfaces/
├── IAuction.sol
├── ICustomNFT.sol
├── ICustomNFTReceiver.sol
├── IFactory.sol
├── IMarketplace.sol
├── IPaymentManager.sol
├── IRegistry.sol
├── IStaking.sol
└── ITreasury.sol

libraries/
├── AccountingMath.sol
├── AuctionMath.sol
├── FeeMath.sol
├── ListingMath.sol
├── OrderHashLib.sol
├── PhaseLogic.sol
└── RewardMath.sol

proxy/
└── interfaces/
    └── IUpgradeableSystem.sol

remix.config.json

🔧 Technology Stack

<p>
  <img src="https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity&logoColor=white" alt="Solidity">
  <img src="https://img.shields.io/badge/OpenZeppelin-Contracts%205.6.1-4E5EE4?logo=openzeppelin&logoColor=white" alt="OpenZeppelin">
  <img src="https://img.shields.io/badge/EIP--712-Typed%20Data-627EEA?logo=ethereum&logoColor=white" alt="EIP-712">
  <img src="https://img.shields.io/badge/UUPS-Upgradeable-6E56CF" alt="UUPS">
  <img src="https://img.shields.io/badge/ERC--1967-Proxy-627EEA?logo=ethereum&logoColor=white" alt="ERC-1967">
  <img src="https://img.shields.io/badge/Remix-Development-00B0D8?logo=remix&logoColor=white" alt="Remix">
</p>

Layer

Technology

Smart contracts

Solidity ^0.8.24

Standard library

OpenZeppelin Contracts 5.6.1

Marketplace upgradeability

UUPS

Proxy

ERC-1967 Proxy

Typed-data signing

EIP-712

Access control

Ownable2Step / AccessControl

Governance primitives

AccessManager / TimelockController

Contract development

Remix configuration included

Settlement asset

Native ETH

⚙️ Security Design

The contracts include several defensive mechanisms:

Role-based authorization

Two-step ownership transfer where applicable

Pausable execution paths

Reentrancy protection

Zero-address validation

Explicit state checks

Expiry validation

Nonce invalidation

Signed-order replay protection

Escrow accounting assertions

Treasury spending limits

Pull-based claim and refund flows

Least-privilege authorization for treasury payers and payment creditors

The repository should still be independently tested, reviewed, and audited before use with production funds.

🧠 Design Principles

The system is structured around a few core engineering principles:

Explicit State

Marketplace listings, offers, auctions, reward programs, and protocol registrations use explicit states and transitions rather than relying only on implicit conditions.

Separation of Concerns

Trading, custody, payments, rewards, deployment, registry management, and governance are split into dedicated contracts.

Accounting Conservation

Value-moving components track escrowed or claimable amounts explicitly so financial state can be checked against contract balances.

Least-Privilege Control

Administrative functionality is divided across roles, ownership, authorized payers, and authorized creditors.

Upgradeability by Boundary

The Marketplace is upgradeable through a UUPS implementation while its proxy remains the stable external address.

🚦 Current Repository Scope

This repository is currently a smart-contract source snapshot containing the protocol contracts, interfaces, libraries, OpenZeppelin dependency snapshot, and Remix configuration.

It does not claim independent security-audit status or production deployment readiness.

Before production deployment, the protocol should go through:

Compilation
    ↓
Unit & Integration Testing
    ↓
Fuzz Testing
    ↓
Invariant Testing
    ↓
Security Review / Audit
    ↓
Deployment Verification
    ↓
Operational Monitoring

📜 License

This project is licensed under the MIT License.

See LICENSE for details.

<div align="center">

🏪 Voryn Marketplace Protocol

<strong>Composable on-chain commerce infrastructure built around explicit state and accountable value flows.</strong>

</div>