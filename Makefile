.PHONY: build test clean deploy-sepolia deploy-local node

test:
	#REPORT_GAS=true npx hardhat test
	npx hardhat test

build:
	npx hardhat compile

node:
	#npx hardhat node
	anvil

fuzz:
	echidna . --contract ServiceNodeContributionEchidnaTest --config echidna-local.config.yml

deploy-local:
	npx hardhat run scripts/deploy-local-test.js --network localhost

deploy-sepolia:
	npx hardhat run scripts/deploy.js --network sepolia

otterscan:
	docker run --rm -p 5100:80 --name otterscan --env ERIGON_URL="http://127.0.0.1:8545" otterscan/otterscan:latest

