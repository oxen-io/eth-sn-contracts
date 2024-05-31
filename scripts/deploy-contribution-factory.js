// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const chalk = require('chalk')

async function main() {

    // Get signers
    [owner] = await ethers.getSigners();

    // Sepolia Arbitrum rewards contract address
    const snRewards = "0xC75A34c31C2b8780a20AfCD75473Ac0Ad82352B6"

    //ServiceNodeRewardsMaster = await ethers.getContractFactory("ServiceNodeRewards");
    //serviceNodeRewards = await ServiceNodeRewardsMaster.connect(snRewards);
    //const designatredToken  = serviceNodeRewards.designatedToken();

    snContributionContractFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
    snContributionFactory = await snContributionContractFactory.deploy(snRewards);

    await snContributionFactory.waitForDeployment();

    console.log(
        '  ',
        chalk.cyan(`Service Node Contribution Factory Contract`),
        'deployed to:',
        chalk.greenBright(await snContributionFactory.getAddress()),
    )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
