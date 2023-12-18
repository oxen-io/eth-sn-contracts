// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const chalk = require('chalk')

async function main() {
    // Deploy a mock ERC20 token
    try {
        // Deploy a mock ERC20 token
        MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20 = await MockERC20.deploy("SENT Token", "SENT", 18);
    } catch (error) {
        console.error("Error deploying MockERC20:", error);
    }

    // Get signers
    [owner, foundationPool] = await ethers.getSigners();

    // Deploy the ServiceNodeRewards contract
    ServiceNodeRewards = await ethers.getContractFactory("ServiceNodeRewards");
    serviceNodeRewards = await ServiceNodeRewards.deploy(
        mockERC20,              // token address
        foundationPool,         // foundation pool address
        15000,                          // staking requirement
        0,                              // liquidator reward ratio
        0,                              // pool share of liquidation ratio
        1                               // recipient ratio
    );

    await serviceNodeRewards.waitForDeployment();
    const leng = serviceNodeRewards.serviceNodesLength();

    console.log(
        '  ',
        chalk.cyan(`Service Node Rewards Contract`),
        'deployed to:',
        chalk.greenBright(await serviceNodeRewards.getAddress()),
    )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
