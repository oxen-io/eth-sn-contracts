.PHONY: build test clean deploy-sepolia deploy-local node

test:
	#REPORT_GAS=true npx hardhat test
	npx hardhat test --parallel --bail

build:
	npx hardhat compile

node:
	npx hardhat node --verbose
	#anvil

analyze:
	# NOTE: (Block) timestamp comparison warnings are ignored (typically
	# vesting or contribution withdrawal delays). At most Arbitrum nodes can
	# rewind time by up to 24 hours or, 1 hr into the future.
	slither . \
		--filter-paths node_modules\|contracts/test \
		--exclude timestamp,naming-convention,assembly

fuzz:
	echidna . --contract ServiceNodeContributionEchidnaTest --config echidna-local.config.yml

deploy-local:
	npx hardhat run scripts/deploy-local-test.js --network localhost

deploy-testnet:
	npx hardhat run scripts/deploy-devnet.js --network arbitrumSepolia

otterscan:
	docker run --rm -p 5100:80 --name otterscan --env ERIGON_URL="http://127.0.0.1:8545" otterscan/otterscan:latest

format-sol:
	npx prettier --write --plugin=prettier-plugin-solidity 'contracts/**/*.sol'

