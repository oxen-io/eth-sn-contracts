const { ethers, upgrades } = require('hardhat');
const chalk = require('chalk')

async function main () {
  const networkName = hre.network.name;
  console.log("Upgrading contracts on:", networkName);

  //Ensure we have API key to verify
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

  const sn_rewards_factory = await ethers.getContractFactory('ServiceNodeRewards');
  console.log('Upgrading SN rewards proxy...');
  serviceNodeRewards = await upgrades.upgradeProxy('0x3433798131A72d99C5779E2B4998B17039941F7b', sn_rewards_factory);
  console.log('SN rewards upgraded');

  console.log("\nVerifying contracts...");

  console.log(chalk.yellow("\n--- Verifying serviceNodeRewards ---\n"));
  serviceNodeRewards.waitForDeployment();
  try {
      await hre.run("verify:verify", {
          address: await serviceNodeRewards.getAddress(),
          constructorArguments: [],
          force: true,
      });
  } catch (error) {}
}
main();
