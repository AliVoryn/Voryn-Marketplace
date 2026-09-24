# Ali Voryn Protocol — Documentation

This directory is the single source of truth for how the protocol is designed, how it behaves, how it is
verified, and how it is deployed. Every document here is written to be read on its own, but they are
deliberately layered: start at the top of the table below and descend only as far as you need.

## Reading paths

Pick the row that matches what you are trying to do.

| I want to… | Read, in order |
| --- | --- |
| Understand what this project is and what it does | [architecture.md](architecture.md) → [features.md](features.md) |
| Look up a specific function, role, event, or error | [contracts.md](contracts.md) |
| Build, test, and run it locally | [local-development.md](local-development.md) |
| Understand the verification philosophy and what is actually proven | [test-strategy.md](test-strategy.md) → [test-matrix.md](test-matrix.md) → [coverage-baseline.md](coverage-baseline.md) |
| Audit the trust model and known limitations | [security.md](security.md) |
| Deploy to a network | [deployment.md](deployment.md) → [preflight.md](preflight.md) |
| Ship to mainnet with governance handoff | [mainnet.md](mainnet.md) → [raffle-mainnet.md](raffle-mainnet.md) |
| Operate the Chainlink automation layer | [AUTOMATION.md](AUTOMATION.md) |
| Understand the CI/quality gates | [LINTING.md](LINTING.md) |

## Document map

| Document | Purpose | Audience |
| --- | --- | --- |
| [architecture.md](architecture.md) | System boundaries, module map, authority model, data flow, design rules | Engineers, auditors |
| [features.md](features.md) | Complete feature catalogue, domain by domain, with the contract that owns each behaviour | Engineers, product |
| [contracts.md](contracts.md) | Contract-by-contract reference: state, external API, roles, events, errors, invariants | Engineers, auditors, integrators |
| [local-development.md](local-development.md) | Toolchain, dependency provenance, build/test/lint workflow, troubleshooting | Contributors |
| [test-strategy.md](test-strategy.md) | Why verification is layered and what each layer is allowed to claim | Engineers, auditors |
| [test-matrix.md](test-matrix.md) | Every suite in `test/`, what it covers, and how to run it in isolation | Engineers, reviewers |
| [coverage-baseline.md](coverage-baseline.md) | Recorded coverage numbers, per-contract branch detail, and reproduction command | Reviewers |
| [security.md](security.md) | Trust boundaries, adversarial model, accounting invariants, known limitations | Auditors, operators |
| [deployment.md](deployment.md) | Full deployment sequence, script reference, environment variables | Operators |
| [preflight.md](preflight.md) | The pre-broadcast gate: what is checked and what aborts a release | Operators |
| [mainnet.md](mainnet.md) | Mainnet release runbook including governance and ownership handoff | Operators, governance |
| [raffle-mainnet.md](raffle-mainnet.md) | Chainlink VRF V2.5 configuration and raffle lifecycle operations | Operators |
| [AUTOMATION.md](AUTOMATION.md) | Chainlink CRE automation boundary, discovery model, gas budget, sequencing | Operators, integrators |
| [LINTING.md](LINTING.md) | Lint scope, exclusions, and the adjudication status of remaining findings | Reviewers |
| [glossary.md](glossary.md) | Precise definitions of the domain terms used across the codebase | Everyone |

## Conventions used in these documents

- **Code blocks labelled `text`** containing `→` arrows represent *conceptual* flow, not literal source.
- **Tables of functions** always mark visibility and the modifier gate that protects the function.
- Numbers are stated with the command that produces them. Where a number is a recorded baseline rather
  than a freshly measured value, the document says so explicitly.
- `src/...` paths are always relative to the repository root.
- "Owner" means the address returned by the contract's `owner()`; "Timelock" means a deployed
  `ProtocolTimelock`. They are the same account in a fully governance-controlled release.

## Documentation accuracy policy

These documents describe the code at the commit they are synced to. Three rules are enforced when editing
them:

1. **No aspirational documentation.** A document may not describe a file, script, workflow, or gate that
   does not exist in the repository at the sync commit.
2. **No unlabelled measurements.** Coverage, gas, and test counts carry either the command that
   reproduces them or an explicit note that they are a recorded baseline from an earlier run.
3. **No implied audit.** Nothing in this directory should be read as an independent security assessment.
   See [security.md](security.md) and [`SECURITY.md`](../SECURITY.md).

Where the documentation and the code disagree, the code is authoritative and the documentation is a bug.

## Related documents outside `docs/`

| Document | Purpose |
| --- | --- |
| [`README.md`](../README.md) | Project front page: overview, feature summary, quickstart |
| [`test/README.md`](../test/README.md) | How the test tree is organised |
| [`verification/README.md`](../verification/README.md) | Mutation and symbolic verification layers |
| [`verification/mutation/README.md`](../verification/mutation/README.md) | Mutation campaign scope and reproduction |
| [`cre/protocol-automation/README.md`](../cre/protocol-automation/README.md) | CRE TypeScript workflow internals, read budget, partitioning |
| [`SECURITY.md`](../SECURITY.md) | Security reporting policy |
| [`LICENSE`](../LICENSE) | MIT |
