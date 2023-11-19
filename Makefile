.PHONY: build test clean deploy-sepolia deploy-local node

build:
	npx hardhat compile

test:
	#REPORT_GAS=true npx hardhat test
	npx hardhat test

node:
	npx hardhat node --vvvv

deploy-local:
	npx hardhat run scripts/deploy.js --network localhost
   
deploy-sepolia:
	npx hardhat run scripts/deploy.js --network sepolia

