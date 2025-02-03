const hre = require("hardhat");
const chalk = require('chalk');
require("./deploy-common.js")();

async function main() {
    const tokenName = "SENT Token";
    const tokenSymbol = "SENT";
    const SENT_UNIT = 1_000_000_000n;
    const SUPPLY = 240_000_000n * SENT_UNIT;
    const POOL_INITIAL = 40_000_000n * SENT_UNIT;
    const STAKING_REQ = 120n * SENT_UNIT;

    const args = {
        SENT_UNIT,
        SUPPLY,
        POOL_INITIAL,
        STAKING_REQ,
    };

    await deployTestnetContracts(tokenName, tokenSymbol, args, false, true /*local_devnet*/);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

