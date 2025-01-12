// This deploys our main token and bridges it over to the L2, intended to replicate mainnet TGE as much as possible
// https://docs.arbitrum.io/build-decentralized-apps/token-bridging/bridge-tokens-programmatically/how-to-bridge-tokens-standard

const hre = require("hardhat");
const chalk = require("chalk");
const { getArbitrumNetwork } = require("@arbitrum/sdk");

const ethers = hre.ethers;

async function main() {
  const SESH_UNIT = 1_000_000_000n;
  const SUPPLY = 240_000_000n * SESH_UNIT;
  //const L1_CHAIN_ID = 1 // mainnet (Sepolia 11155111)
  //const L2_CHAIN_ID = 42161 // ARB (ARB Sepolia 421614)
  const L1_CHAIN_ID = 11155111; // Sepolia
  const L2_CHAIN_ID = 421614; // ARB Sepolia

  const args = {
    SESH_UNIT,
    SUPPLY,
    L1_CHAIN_ID,
    L2_CHAIN_ID,
  };

  const { seshERC20 } = await deploySESH(args);
  await bridgeSESH(seshERC20, args);
}

async function deploySESH(args = {}, verify = true) {
  [owner] = await ethers.getSigners();
  const ownerAddress = await owner.getAddress();

  const networkName = hre.network.name;
  console.log("Deploying SESH contract to:", chalk.yellow(networkName));

  if (verify) {
    let apiKey;
    if (typeof hre.config.etherscan?.apiKey === "object") {
      apiKey = hre.config.etherscan.apiKey[networkName];
    } else {
      apiKey = hre.config.etherscan?.apiKey;
    }
    if (!apiKey || apiKey == "") {
      console.error(
        chalk.red("Error: API key for contract verification is missing."),
      );
      console.error(
        "Please set it in your Hardhat configuration under 'etherscan.apiKey'.",
      );
      process.exit(1);
    }
  }
  const SESH_UNIT = args.SESH_UNIT || 1_000_000_000n;
  const SUPPLY = args.SUPPLY || 240_000_000n * SESH_UNIT;

  const SeshERC20 = await ethers.getContractFactory("SESH", owner);
  let seshERC20;

  try {
    seshERC20 = await SeshERC20.deploy(SUPPLY, ownerAddress);
  } catch (error) {
    console.error("Failed to deploy SESH contract:", error);
    process.exit(1);
  }

  console.log(
    "  ",
    chalk.cyan(`SESH Contract`),
    "deployed to:",
    chalk.greenBright(await seshERC20.getAddress()),
    "on network:",
    chalk.yellow(networkName),
  );
  console.log(
    "  ",
    "Initial Supply will be received by:",
    chalk.green(ownerAddress),
  );
  await seshERC20.waitForDeployment();

  if (verify) {
    console.log(chalk.yellow("\n--- Verifying SESH ---\n"));
    console.log("Waiting 6 confirmations to ensure etherscan has processed tx");
    await seshERC20.deploymentTransaction().wait(6);
    console.log("Finished Waiting");
    try {
      await hre.run("verify:verify", {
        address: await seshERC20.getAddress(),
        constructorArguments: [SUPPLY, ownerAddress],
        contract: "contracts/SESH.sol:SESH",
        force: true,
      });
    } catch (error) {
      console.error(chalk.red("Verification failed:"), error);
    }
    console.log(chalk.green("Contract verification complete."));
  }

  return { seshERC20 };
}

async function bridgeSESH(l1ERC20Contract, args = {}) {
  [owner] = await ethers.getSigners();
  const L1_CHAIN_ID = args.L1_CHAIN_ID || 1; // mainnet
  const L2_CHAIN_ID = args.L2_CHAIN_ID || 42161; // Arbitrum One

  const ownerAddress = await owner.getAddress();
  const l1TokenAddress = await l1ERC20Contract.getAddress();

  const l2Network = await getArbitrumNetwork(L2_CHAIN_ID);
  let l1Name, l2Name
  for (const networkName of Object.keys(hre.config.networks)) {
    const networkConfig = hre.config.networks[networkName];
    if (networkConfig.chainId === L1_CHAIN_ID) {
      let l1Url = networkConfig.url
      l1Name = networkName
    }
    if (networkConfig.chainId === L2_CHAIN_ID) {
      l2Url = networkConfig.url
      l2Name = networkName
    }
  }
  const l2Provider = new ethers.JsonRpcProvider(l2Url);

  console.log(
    `\nBridging tokens from L1: ${l1Name} (${L1_CHAIN_ID}) to L2 ${l2Name} (${L2_CHAIN_ID})...`,
  );

  // Instantiate contracts
  const l1GatewayRouter = new ethers.Contract(
    l2Network.tokenBridge.parentGatewayRouter,
    [
      "function getGateway(address token) view returns (address)",
      "function outboundTransferCustomRefund( address _token, address _refundTo, address _to, uint256 _amount, uint256 _maxGas, uint256 _gasPriceBid, bytes calldata _data) external payable returns (bytes memory)",
      "function calculateL2TokenAddress(address l1ERC20) view returns (address)",
    ],
    owner,
  );

  const l1ERC20Gateway = await l1GatewayRouter.getGateway(l1TokenAddress);
  const l2TokenAddress =
  await l1GatewayRouter.calculateL2TokenAddress(l1TokenAddress);
  console.log("  ", "Calculated L2TokenAddress: ", chalk.green(l2TokenAddress));

  // Approve the token for the gateway
  const tokensToSend = "200000000"
  const depositAmount = ethers.parseUnits(tokensToSend, 9);
  console.log(`   Approving ${tokensToSend} SESH for L1 Gateway...`);
  const approveTx = await l1ERC20Contract.approve(l1ERC20Gateway, depositAmount);
  await approveTx.wait();

  // Calculate retryable ticket parameters
  const l1MaxGas = BigInt(300000);
  const l2MaxGas = BigInt(1000000);
  const feeData = await owner.provider.getFeeData();
  const l1GasPriceBid = feeData.gasPrice * BigInt(2);
  if (!l1GasPriceBid) {
    console.log("no gas price data");
    l1GasPriceBid = ethers.parseUnits('10', 'gwei');
  }
  const l2GasPriceBid = BigInt("1000000000");
  const maxSubmissionCost = BigInt("500000000000000");
  const callHookData = "0x";
  const l2amount = ethers.parseEther("0.002");
  const totalL2GasCost = l2MaxGas * l2GasPriceBid;
  const totalL2Value = maxSubmissionCost + totalL2GasCost + l2amount;

  const extraData = ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256", "bytes"],
    [maxSubmissionCost, callHookData],
  );

  // Execute outbound transfer
  console.log(`   Initiating outbound transfer...`);
  const outboundTx = await l1GatewayRouter.outboundTransferCustomRefund(
    l1TokenAddress,
    ownerAddress,
    ownerAddress,
    depositAmount,
    l2MaxGas,
    l2GasPriceBid,
    extraData,
    {
      gasLimit: l1MaxGas,
      gasPrice: l1GasPriceBid,
      value: totalL2Value,
    },
  );

  const receipt = await outboundTx.wait();
  console.log(`   Outbound transfer submitted: ${receipt.hash}`);

  // Generate link to Arbitrum Retryable Dashboard
  const retryableDashboardLink = `https://retryable-dashboard.arbitrum.io/tx/${receipt.hash}`;
  console.log(`   Track the retryable ticket here: ${retryableDashboardLink}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
