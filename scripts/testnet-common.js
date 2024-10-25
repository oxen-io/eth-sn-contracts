// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const chalk = require('chalk')

async function deployTestnetContracts(tokenName, tokenSymbol, args = {}, verify = true) {

    const networkName = hre.network.name;
    console.log("Deploying contracts to:", networkName);

    if (verify) {
        let apiKey;
        if (typeof hre.config.etherscan?.apiKey === 'object') {
            apiKey = hre.config.etherscan.apiKey[networkName];
        } else {
            apiKey = hre.config.etherscan?.apiKey;
        }
        if (!apiKey || apiKey == "") {
            console.error(chalk.red("Error: API key for contract verification is missing."));
            console.error("Please set it in your Hardhat configuration under 'etherscan.apiKey'.");
            process.exit(1); // Exit with an error code
        }
    }
    const SENT_UNIT = args.SENT_UNIT || 1_000000000n;
    const SUPPLY = args.SUPPLY || 240_000_000n * SENT_UNIT;
    const POOL_INITIAL = args.POOL_INITIAL || 40_000_000n * SENT_UNIT;
    const STAKING_REQ = args.STAKING_REQ || 20_000n * SENT_UNIT;

    MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = null
    if (args.TOKEN_ADDRESS) {
        mockERC20 = await MockERC20.attach(args.TOKEN_ADDRESS);
    } else {
        try { // Deploy a mock ERC20 token
            mockERC20    = await MockERC20.deploy(tokenName, tokenSymbol, SUPPLY);
            tokenAddress = await mockERC20.getAddress()
        } catch (error) {
            console.error("Failed to deploy Testnet contracts, error when deploying MockERC20 contract:", error);
            return;
        }
    }

    // Get signers
    [owner] = await ethers.getSigners();

    RewardRatePool = await ethers.getContractFactory("TestnetRewardRatePool");
    rewardRatePool = await upgrades.deployProxy(RewardRatePool, [await owner.getAddress(), await mockERC20.getAddress()]);

    await mockERC20.transfer(rewardRatePool, POOL_INITIAL);

    // Deploy the ServiceNodeRewards contract
    ServiceNodeRewardsMaster = await ethers.getContractFactory("TestnetServiceNodeRewards");
    serviceNodeRewards = await upgrades.deployProxy(ServiceNodeRewardsMaster,[
        await mockERC20.getAddress(),      // token address
        await rewardRatePool.getAddress(), // foundation pool address
        STAKING_REQ,                       // staking requirement
        10,                                // max contributors
        2,                                 // liquidator reward ratio
        0,                                 // pool share of liquidation ratio
        998                                // recipient ratio
    ]);
    await serviceNodeRewards.waitForDeployment();

    snContributionContractFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
    snContributionFactory         = await upgrades.deployProxy(snContributionContractFactory,
                                                               [await serviceNodeRewards.getAddress()]);
    await snContributionFactory.waitForDeployment();

    rewardRatePool.setBeneficiary(serviceNodeRewards);

    console.log(
        '  ',
        chalk.cyan(`${tokenSymbol} (${tokenName}) Contract`),
        'deployed to:',
        chalk.greenBright(await mockERC20.getAddress()),
    )
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
        chalk.cyan(`Service Node Contribution Factory Contract`),
        'deployed to:',
        chalk.greenBright(await snContributionFactory.getAddress()),
    )

    if (verify) {
      // Add verify task runners
      console.log("\nVerifying contracts...");

      console.log(chalk.yellow("\n--- Verifying mockERC20 ---\n"));
      mockERC20.waitForDeployment();
      try {
          await hre.run("verify:verify", {
              address: await mockERC20.getAddress(),
              constructorArguments: [tokenName, tokenSymbol, SUPPLY],
              contract: "contracts/test/MockERC20.sol:MockERC20",
              force: true,
          });
      } catch (error) {}

      console.log(chalk.yellow("\n--- Verifying rewardRatePool ---\n"));
      rewardRatePool.waitForDeployment();
      try {
          await hre.run("verify:verify", {
              address: await rewardRatePool.getAddress(),
              constructorArguments: [],
              force: true,
          });
      } catch (error) {}

      console.log(chalk.yellow("\n--- Verifying serviceNodeRewards ---\n"));
      serviceNodeRewards.waitForDeployment();
      try {
          await hre.run("verify:verify", {
              address: await serviceNodeRewards.getAddress(),
              constructorArguments: [],
              force: true,
          });
      } catch (error) {}

      console.log(chalk.yellow("\n--- Verifying snContributionFactory ---\n"));
      snContributionFactory.waitForDeployment();
      try {
          await hre.run("verify:verify", {
              address: await snContributionFactory.getAddress(),
              constructorArguments: [],
              force: true,
          });
      } catch (error) {}

      console.log("Contract verification complete.");
    }
}

module.exports = function() {
    this.deployTestnetContracts = deployTestnetContracts;
};
