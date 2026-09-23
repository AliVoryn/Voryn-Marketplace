SHELL := /usr/bin/env bash

.PHONY: setup fmt-check fmt build test fuzz invariant coverage snapshot lint fork preflight verify-deployment mutation symbolic cre-install cre-typecheck cre-test clean

setup:
	bash ./script/install-dependencies.sh

fmt-check:
	forge fmt --check

fmt:
	forge fmt

build:
	forge build --sizes

test:
	forge test -vvv

fuzz:
	FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'

invariant:
	FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'

coverage:
	forge coverage --report summary --no-match-path 'script/**'

snapshot:
	forge snapshot

lint:
	forge lint

fork:
	forge test --match-path 'test/**/*.Fork.t.sol' -vvvv

preflight:
	: "$${RPC_URL:?RPC_URL is required}"
	forge script script/Preflight.s.sol --rpc-url "$${RPC_URL}"

verify-deployment:
	: "$${RPC_URL:?RPC_URL is required}"
	forge script script/VerifyDeployment.s.sol --rpc-url "$${RPC_URL}"

mutation:
	./verification/mutation/run.sh

symbolic:
	./verification/symbolic/run.sh

cre-install:
	cd cre/protocol-automation && npm ci

cre-typecheck:
	cd cre/protocol-automation && npm run typecheck

cre-test:
	cd cre/protocol-automation && npm test

clean:
	forge clean
