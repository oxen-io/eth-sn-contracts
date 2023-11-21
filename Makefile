.PHONY: build test clean deploy-sepolia deploy-local node

test:
	#REPORT_GAS=true npx hardhat test
	npx hardhat test

build:
	npx hardhat compile

node:
	npx hardhat node

deploy-local:
	npx hardhat run scripts/deploy.js --network localhost
   
deploy-sepolia:
	npx hardhat run scripts/deploy.js --network sepolia

