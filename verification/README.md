# Verification tooling

This directory contains verification layers that complement the Foundry test suite.

`mutation/` evaluates test-suite strength by introducing controlled source mutations.

`symbolic/` contains small, high-value arithmetic and monotonicity properties for Solidity's SMT checker.
Run it with `./verification/symbolic/run.sh`; it requires Solidity 0.8.24 and a solc-compatible Z3 or
CVC4 library. The script fails if solc reports that no solver is available, rather than silently passing
without analyzing the harnesses.

Neither layer is used as a substitute for behavioral, fuzz, invariant, integration, fork, deployment, or security tests.
