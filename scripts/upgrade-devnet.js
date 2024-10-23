const { ethers, upgrades } = require('hardhat');
async function main () {
  const sn_rewards_factory = await ethers.getContractFactory('ServiceNodeRewards');
  console.log('Upgrading SN rewards factory...');
  await upgrades.upgradeProxy('0x3433798131A72d99C5779E2B4998B17039941F7b', sn_rewards_factory);
  console.log('SN rewards upgraded');
}
main();
