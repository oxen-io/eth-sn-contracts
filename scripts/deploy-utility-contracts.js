const hre = require("hardhat");

// === Global constants for constructor parameters ===
// TODO SET THESE WITH ACTUAL ADDRESSES AND PARAMETERS
const TOKEN_A_ADDRESS       = "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const TOKEN_B_ADDRESS       = "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
const INITIAL_NUMERATOR     = 100;
const INITIAL_DENOMINATOR   = 1;

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
    const TokenConverter = await hre.ethers.getContractFactory("TokenConverter");

    console.log("Deploying TokenConverter...");
    const tokenConverter = await TokenConverter.deploy(
        TOKEN_A_ADDRESS,
        TOKEN_B_ADDRESS,
        INITIAL_NUMERATOR,
        INITIAL_DENOMINATOR
    );

    console.log("TokenConverter deployed to:", await tokenConverter.getAddress());

    console.log("Waiting for Etherscan to index the contract...");
    await sleep(30_000);

    console.log("Verifying contract on Etherscan...");
    try {
        await hre.run("verify:verify", {
            address: tokenConverter.address,
            constructorArguments: [
                TOKEN_A_ADDRESS,
                TOKEN_B_ADDRESS,
                INITIAL_NUMERATOR,
                INITIAL_DENOMINATOR,
            ],
    });
    console.log("Contract verified successfully.");
    } catch (error) {
        console.error("Failed to verify contract on Etherscan:", error);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Error deploying TokenConverter:", error);
        process.exit(1);
    });

