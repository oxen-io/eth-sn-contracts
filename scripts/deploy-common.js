// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const chalk = require('chalk')

async function deployTestnetContracts(tokenName, tokenSymbol, args = {}, verify = true, local_devnet = false) {
    args.TOKEN_NAME   = tokenName;
    args.TOKEN_SYMBOL = tokenSymbol;
    args.local_devnet = local_devnet;
    return deployContracts(args, verify);
}

async function deployContracts(args = {}, verify = true) {
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
    const TOKEN_NAME     = args.TOKEN_NAME     || "SESH Token";
    const TOKEN_SYMBOL   = args.TOKEN_SYMBOL   || "SESH";
    const SESH_UNIT = args.SESH_UNIT || 1_000000000n;
    const SUPPLY = args.SUPPLY || 240_000_000n * SESH_UNIT;
    const POOL_INITIAL = args.POOL_INITIAL || 40_000_000n * SESH_UNIT;
    const STAKING_REQ = args.STAKING_REQ || 20_000n * SESH_UNIT;
    const TOKEN_ADDRESS  = args.TOKEN_ADDRESS  || "";
    const local_devnet = args.local_devnet || false;
    const mainnet = args.mainnet || false;

    MockERC20 = await ethers.getContractFactory("MockERC20");
    tokenContract = null
    if (TOKEN_ADDRESS) {
        tokenContract = await MockERC20.attach(TOKEN_ADDRESS);
    } else {
        try { // Deploy a mock ERC20 token
            tokenContract = await MockERC20.deploy(TOKEN_NAME, TOKEN_SYMBOL, SUPPLY);
        } catch (error) {
            console.error("Failed to deploy Testnet contracts, error when deploying MockERC20 contract:", error);
            return;
        }
    }

    // Get signers
    [owner] = await ethers.getSigners();

    const rewardPoolFactoryName = mainnet ? "RewardRatePool" : "TestnetRewardRatePool";
    RewardRatePool = await ethers.getContractFactory(rewardPoolFactoryName);
    rewardRatePool = await upgrades.deployProxy(RewardRatePool, [await owner.getAddress(), await tokenContract.getAddress()]);

    await tokenContract.transfer(rewardRatePool, POOL_INITIAL);

    // Deploy the ServiceNodeRewards contract
    let serviceNodeRewardsDeployContract;
    if (mainnet) {
        serviceNodeRewardsDeployContract = "ServiceNodeRewards";
    } else {
        serviceNodeRewardsDeployContract = local_devnet ? "LocalDevnetServiceNodeRewards" : "TestnetServiceNodeRewards";
    }
    ServiceNodeRewardsMaster = await ethers.getContractFactory(serviceNodeRewardsDeployContract);

    serviceNodeRewards = await upgrades.deployProxy(ServiceNodeRewardsMaster,[
        await tokenContract.getAddress(),  // token address
        await rewardRatePool.getAddress(), // foundation pool address
        STAKING_REQ,                       // staking requirement
        10,                                // max contributors
        3,                                 // liquidator reward ratio
        17,                                // pool share of liquidation ratio
        9980                               // recipient ratio
    ]);
    await serviceNodeRewards.waitForDeployment();

    snContributionContractFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
    snContributionFactory         = await upgrades.deployProxy(snContributionContractFactory,
                                                               [await serviceNodeRewards.getAddress()]);
    await snContributionFactory.waitForDeployment();

    rewardRatePool.setBeneficiary(serviceNodeRewards);

    console.log(
        '  ',
        chalk.cyan(`ERC20 Contract`),
        'deployed to:',
        chalk.greenBright(await tokenContract.getAddress()),
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

      if (!args.TOKEN_ADDRESS) {
          console.log(chalk.yellow("\n--- Verifying mockERC20 ---\n"));
          tokenContract.waitForDeployment();
          try {
              await hre.run("verify:verify", {
                  address: await tokenContract.getAddress(),
                  constructorArguments: [TOKEN_NAME, TOKEN_SYMBOL, SUPPLY],
                  contract: "contracts/test/MockERC20.sol:MockERC20",
                  force: true,
              });
          } catch (error) {}
      }

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
    this.deployContracts = deployContracts;
};
