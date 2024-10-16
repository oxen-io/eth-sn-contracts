const hre   = require("hardhat");
const chalk = require('chalk')

async function main() {
    // NOTE: Deploy tokens
    token_deployer = await ethers.getContractFactory("MockERC20");
    token          = await token_deployer.deploy("SENT Token", "SENT", 9);
    [owner]        = await ethers.getSigners();

    // NOTE: Deploy the reward pool contract
    const reward_rate_pool_deployer = await ethers.getContractFactory("RewardRatePool");
    const reward_rate_pool          = await upgrades.deployProxy(reward_rate_pool_deployer, [await owner.getAddress(), await token.getAddress()]);
    await reward_rate_pool.waitForDeployment();

    // NOTE: Fund the reward pool
    await token.transfer(reward_rate_pool, 40_000_000n * BigInt(1e9));

    // NOTE: Deploy the rewards contract
    const sn_rewards_deployer = await ethers.getContractFactory("ServiceNodeRewards");
    const sn_rewards          = await upgrades.deployProxy(sn_rewards_deployer, [
        await token.getAddress(),            // token address
        await reward_rate_pool.getAddress(), // foundation pool address
        120n * BigInt(1e9),                  // staking requirement
        10,                                  // max contributors
        1,                                   // liquidator reward ratio
        0,                                   // pool share of liquidation ratio
        1                                    // recipient ratio
    ]);
    await sn_rewards.waitForDeployment();

    // NOTE: Deploy the multi contribution factory
    const sn_contrib_factory_deployer = await ethers.getContractFactory("ServiceNodeContributionFactory");
    const sn_contrib_factory          = await sn_contrib_factory_deployer.deploy(await sn_rewards.getAddress());
    await sn_contrib_factory.waitForDeployment();

    // NOTE: Output contract addresses
    console.log('  ', chalk.cyan(`Service Node Rewards Contract`), '    deployed to:', chalk.greenBright(await sn_rewards.getAddress()))
    console.log('  ', chalk.cyan(`Service Node Contribution Factory`), 'deployed to:', chalk.greenBright(await sn_contrib_factory.getAddress()))
    console.log('  ', chalk.cyan(`Reward Rate Pool Contract`), '        deployed to:', chalk.greenBright(await reward_rate_pool.getAddress()))
    console.log('  ', chalk.cyan(`SENT Contract Address`), '            deployed to:', chalk.greenBright(await token.getAddress()))
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
