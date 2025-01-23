//TODO set this before running
const TOKEN_ADDRESS = "";

async function main() {
    if (!TOKEN_ADDRESS) {
        console.error("Error: TOKEN_ADDRESS cannot be empty. Please set the TOKEN_ADDRESS variable before running. This likely means you want to call the deploy and bridge script first");
        process.exitCode = 1;
        return;
    }

    const SESH_UNIT = 1_000_000_000n;
    const SUPPLY = 240_000_000n * SESH_UNIT;
    const POOL_INITIAL = 40_000_000n * SESH_UNIT;
    
    //TODO change this to the actual staking requirement
    //const STAKING_REQ = 120n * SESH_UNIT;
    console.error("Error: set STAKING_REQ");
    process.exitCode = 1;
    return;

    const args = {
        SESH_UNIT,
        SUPPLY,
        POOL_INITIAL,
        STAKING_REQ,
        TOKEN_ADDRESS,
    };

    await deployContracts(args);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

