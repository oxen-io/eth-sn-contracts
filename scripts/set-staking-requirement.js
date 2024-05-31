const chalk = require('chalk')
const fs = require('fs')

let stakingRequirement = 120;
let newStakingRequirement = ethers.parseUnits(stakingRequirement.toString(), 9);
let rewardsContractAddress = "0xC75A34c31C2b8780a20AfCD75473Ac0Ad82352B6";

async function main() {
    const [deployer] = await ethers.getSigners();
    const ServiceNodeRewards = await ethers.getContractFactory("ServiceNodeRewards");

    console.log("Setting service node rewards staking requirement with address:", deployer.address);

    console.log("Account balance:", (await deployer.getBalance()).toString());

    console.log(
        '  ',
        chalk.cyan("Service Node Rewards"),
        'contract address: ',
        chalk.greenBright(),
    )

    const serviceNodeRewards = await ServiceNodeRewards.attach(rewardsContractAddress);

    const transaction = await serviceNodeRewards.setStakingRequirement(newStakingRequirement);

    console.log(transaction);

    console.log(
        '  ',
        chalk.cyan("ServiceNodeRewards"),
        'set stakingRequirement to: ',
        chalk.greenBright(stakingRequirement),
    );

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
