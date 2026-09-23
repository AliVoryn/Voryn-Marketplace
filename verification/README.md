# Verification tooling

This directory contains verification layers that complement the Foundry test suite.

`mutation/` evaluates test-suite strength by introducing controlled source mutations.

`symbolic/` contains small, high-value arithmetic and monotonicity properties suitable for Solidity's SMT checker.

Neither layer is used as a substitute for behavioral, fuzz, invariant, integration, fork, deployment, or security tests.
