// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const chalk = require('chalk')

let principal = 40000000;
let bigAtomicPrincipal = ethers.parseUnits(principal.toString(), 9);

async function main() {
    // Deploy a mock ERC20 token
    try {
        // Deploy a mock ERC20 token
        MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20 = await MockERC20.deploy("SENT Token", "SENT", 9);
    } catch (error) {
        console.error("Error deploying MockERC20:", error);
    }

    // Get signers
    [owner] = await ethers.getSigners();

    RewardRatePool = await ethers.getContractFactory("RewardRatePool");
    rewardRatePool = await upgrades.deployProxy(RewardRatePool, [await owner.getAddress(), await mockERC20.getAddress()]);

    await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);

    // Deploy the ServiceNodeRewards contract
    ServiceNodeRewardsMaster = await ethers.getContractFactory("ServiceNodeRewards");
    serviceNodeRewards = await upgrades.deployProxy(ServiceNodeRewardsMaster,[
        await mockERC20.getAddress(),              // token address
        await rewardRatePool.getAddress(),         // foundation pool address
        120_000_000_000,                           // staking requirement
        10,                                        // max contributors
        0,                                         // liquidator reward ratio
        0,                                         // pool share of liquidation ratio
        1                                          // recipient ratio
    ]);


    await serviceNodeRewards.waitForDeployment();
    const leng = serviceNodeRewards.serviceNodesLength();

    console.log(
        '  ',
        chalk.cyan(`Service Node Rewards Contract`),
        'deployed to:',
        chalk.greenBright(await serviceNodeRewards.getAddress()),
    )
    console.log(
        '  ',
        chalk.cyan(`Reward Rate Pool Contract`),
        'deployed to:',
        chalk.greenBright(await rewardRatePool.getAddress()),
    )
    console.log(
        '  ',
        chalk.cyan(`SENT Contract Address`),
        'deployed to:',
        chalk.greenBright(await mockERC20.getAddress()),
    )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
