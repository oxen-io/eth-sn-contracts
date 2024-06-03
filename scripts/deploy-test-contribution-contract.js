const chalk = require('chalk');
const { ethers } = require('hardhat');

//const sentContractAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const sentContractAddress = "0xbF3e23d546D19302e911AAc26B3c01A73c7De380";
const factoryAddress = "0x06b8F568F9ed3E2f0393892b374437D253b733E7";

async function main() {
    //const feeData = await provider.getFeeData();
    const [deployer] = await ethers.getSigners();
    const ServiceNodeContributionFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");

    console.log("Deploying service node contribution contract with address:", chalk.green(deployer.address));

    const snContributionFactory = await ServiceNodeContributionFactory.attach(factoryAddress);

    console.log(
        '  ',
        chalk.cyan("Attached to ServiceNodeContributionFactory at:"),
        chalk.greenBright(factoryAddress)
    );

    const transaction = await snContributionFactory.deployContributionContract([1, 2], [3, 4, 5, 6]);
    const receipt = await transaction.wait();
    const snContributionAddress = ethers.getAddress(receipt.logs[0].topics[1].substr(26));

    console.log(
        '  ',
        chalk.cyan("Deployed ServiceNodeContribution contract at:"),
        chalk.greenBright(snContributionAddress)
    );

    const ServiceNodeContribution = await ethers.getContractFactory("ServiceNodeContribution");
    const snContribution = await ServiceNodeContribution.attach(snContributionAddress);
    const tokenABI = [ "function balanceOf(address owner) view returns (uint256)", "function approve(address spender, uint256 amount) returns (bool)" ];
    const sentToken = await ethers.getContractAt(tokenABI, sentContractAddress)

    console.log(
        '  ',
        chalk.cyan("Attached to SENT token at:"),
        chalk.greenBright(sentContractAddress)
    );

    const minContribution = await snContribution.minimumContribution();
    await sentToken.approve(snContributionAddress, minContribution + BigInt(1));
    await snContribution.connect(deployer).contributeOperatorFunds(minContribution, [3,4,5,6], {
        gasLimit: 1000000,
    })
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

