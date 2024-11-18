const hre = require("hardhat");

const STAKING_TEST_AMNT = 15000000000000
const BLS_NODES =
[
  {
    blsPubkey: {
      X: BigInt("0x28852e6bd8fc98305370c1636e35d3b1fe30cb5d79e5392b1238f18a1f60a1ed"),
      Y: BigInt("0x1d0a9ed200fc6762ce53b42d6c9173a11c233a8e41d634ec7014c00ebb5ed4b0"),
    },
    blsSig: {
      sigs0: BigInt("0x27ceb4fb24b0cb43c55af0ce2f6463e6d14ec1c7f9edbad7c00fbb31a38e3d53"),
      sigs1: BigInt("0x2386070cdd9a315241a8d351e2185addc042ad36aca524ad93a7862ac452b9a1"),
      sigs2: BigInt("0x2170a69f683f44baabf1c590e6c5863a0d30b84d50144cb2f8cc8cb105fad7e9"),
      sigs3: BigInt("0x0d9e3b16e83584504b5a597e98cfa76f9d7487878b6a03677beed56fe7a1ba39"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x3621a81c1ef05d48fc9be9dd590ab0869a70fa751e40d8fbebdb0d90e285dbd8"),
      serviceNodeSignature1: BigInt("0x9812e9d91f4e468c56f77fdbb6735b50c2c3590055efb38f26796a4630d4da42"),
      serviceNodeSignature2: BigInt("0x40779f125038351141f70f5e8d24cc1b70abcd466a28847551cc1496c13ae209"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x137e85cd37748f14247358e0e44612210aa5fa27a8fbf28ad340c55767f15d2c"),
      Y: BigInt("0x18edb0ca60f8acb2632f940b18ac6ca4600f10f2b266c9d6c5e20124ede3bb8b"),
    },
    blsSig: {
      sigs0: BigInt("0x1d041dfbf3d6c94c4d171f53faae08fdf1124d9a4286e5d54dcc243e88a96a4f"),
      sigs1: BigInt("0x161c04dbf785039cdf5fea0f78a5b481f4daa7049b39a5fdec0a6e735ff09775"),
      sigs2: BigInt("0x26337d0059f0df7311a968162a7c2951aaa3bfc22213f88167ca06777d8f6469"),
      sigs3: BigInt("0x13149ba06fd741964f0068e4691b20417d221d9742ded83ab1db5d2ecb5129d5"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x60a9ab78cf2f4fd0389ca6044c340583089d7aaf85cfa3f273145d9188698c84"),
      serviceNodeSignature1: BigInt("0xd345006a1d3c05e78acf5009518654ccee0e91a3c283f3318ad8038ef39efda0"),
      serviceNodeSignature2: BigInt("0x5bd67009d57f0e225374d85877497916705cc6d486785c377cec6e48ffb3c608"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  }
];

async function main() {

  const networkName = hre.network.name;
  let apiKey;
  if (typeof hre.config.etherscan?.apiKey === 'object') {
      apiKey = hre.config.etherscan.apiKey[networkName];
  } else {
      apiKey = hre.config.etherscan?.apiKey;
  }
  if (!apiKey || apiKey == "") {
      console.error("Error: API key for contract verification is missing.");
      console.error("Please set it in your Hardhat configuration under 'etherscan.apiKey'.");
      process.exit(1); // Exit with an error code
  }

  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  sentTokenContractFactory      = await ethers.getContractFactory("MockERC20");
  snRewardsContractFactory      = await ethers.getContractFactory("MockServiceNodeRewards");
  snContributionContractFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
  sentToken             = await sentTokenContractFactory.deploy("SENT Token", "SENT", 240_000_000n * 1_000_000_000n);
  snRewards             = await snRewardsContractFactory.deploy(sentToken, STAKING_TEST_AMNT);
  snContributionFactory = await upgrades.deployProxy(snContributionContractFactory, [await snRewards.getAddress()]);

  // Prepare constructor arguments
  const _stakingRewardsContract = await snRewards.getAddress();
  const _maxContributors = 10;

  // IServiceNodeRewards.ReservedContributor[] memory reserved
  const reserved = [];

  // Deploy ServiceNodeContribution
  const ServiceNodeContribution = await hre.ethers.getContractFactory("ServiceNodeContribution");
  const node = BLS_NODES[0];
  const serviceNodeContribution = await ServiceNodeContribution.deploy(
    _stakingRewardsContract,
    _maxContributors,
    node.blsPubkey,
    node.blsSig,
    node.snParams,
    node.reserved,
    false
  );
  await serviceNodeContribution.waitForDeployment();
  console.log("ServiceNodeContribution deployed to:", await serviceNodeContribution.getAddress());

  // Verify the contract on Etherscan
  try {
    await hre.run("verify:verify", {
      address: await serviceNodeContribution.getAddress(),
      constructorArguments: [
        _stakingRewardsContract,
        _maxContributors,
        node.blsPubkey,
        node.blsSig,
        node.snParams,
        node.reserved,
        false
      ],
    });
    console.log("Contract verified on Etherscan");
  } catch (e) {
    console.error("Verification failed:", e);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

