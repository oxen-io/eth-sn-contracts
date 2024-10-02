const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT = 50000000000000

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
        staker: {
            addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
            beneficiary: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        },
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
];

describe("TokenVestingStaking Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let MockServiceNodeRewards;
    let mockServiceNodeRewards;
    let TokenVestingStaking;
    let tokenVestingStaking;
    let owner;
    let beneficiary;

    beforeEach(async function () {
        // Deploy a mock ERC20 token
        try {
            // Deploy a mock ERC20 token
            MockERC20 = await ethers.getContractFactory("MockERC20");
            mockERC20 = await MockERC20.deploy("SENT Token", "SENT", 9);
        } catch (error) {
            console.error("Error deploying MockERC20:", error);
        }

        // Get signers
        [owner, beneficiary, contributor, anotherContributor] = await ethers.getSigners();

        MockServiceNodeRewards = await ethers.getContractFactory("MockServiceNodeRewards");
        mockServiceNodeRewards = await MockServiceNodeRewards.deploy(mockERC20, STAKING_TEST_AMNT);

        // Deploy ServiceNodeContributionFactory
        ServiceNodeContributionFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
        serviceNodeContributionFactory = await ServiceNodeContributionFactory.deploy(mockServiceNodeRewards.getAddress());

        let start = await time.latest() + 5;
        let end = start + 2 * 365 * 24 * 60 * 60; // + 2 Years
        time.setNextBlockTimestamp(await time.latest() + 4);

        TokenVestingStaking = await ethers.getContractFactory("TokenVestingStaking");
        tokenVestingStaking = await TokenVestingStaking.deploy(beneficiary,
                                                               /*revoker*/ owner,
                                                               start,
                                                               end,
                                                               /*transferableBeneficiary*/ true,
                                                               /*rewardsContract*/ mockServiceNodeRewards,
                                                               serviceNodeContributionFactory,
                                                               mockERC20);

        await mockERC20.transfer(tokenVestingStaking, TEST_AMNT);
        await mockERC20.transfer(mockServiceNodeRewards, TEST_AMNT);

    });

    it("Should deploy and set the correct revoker", async function () {
        expect(await tokenVestingStaking.revoker()).to.equal(await owner.getAddress());
    });

    it("Should deploy and set the correct beneficiary", async function () {
        expect(await tokenVestingStaking.beneficiary()).to.equal(await beneficiary.getAddress());
    });

    describe("Add solo node", function () {
        beforeEach(async function () {
            // NOTE: Register a node
            const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking);
            const node          = BLS_NODES[0];
            await tokenVestingStaking.connect(beneficiary).addBLSPublicKey(node.blsPubkey,
                                                                           node.blsSig,
                                                                           node.snParams,
                                                                           beneficiary);
            const balanceAfter = await mockERC20.balanceOf(tokenVestingStaking);
            expect(balanceBefore - balanceAfter).to.equal(STAKING_TEST_AMNT);
        });

        it("Should be able to claim rewards", async function () {
            const balanceBefore = await mockERC20.balanceOf(beneficiary);
            await mockServiceNodeRewards.connect(beneficiary).claimRewards();
            const balanceAfter = await mockERC20.balanceOf(beneficiary);
            expect(balanceAfter - balanceBefore).to.equal(50);

            // NOTE: Expect claim on the investor contract to fail because the node has not had its
            // stake unlocked yet.
            expect(await tokenVestingStaking.connect(beneficiary).claimRewards()).to.be.reverted;
        });

        it("Should be able to unstake and claim rewards", async function () {

            const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking);
            await mockServiceNodeRewards.removeBLSPublicKeyWithSignature(/*serviceNodeID*/ 1,0,0,0,0,0,0,[]);

            // TODO: The mock adds +50 $SENT everytime we claim, using mocks
            // isn't great because we're not actually testing against the real
            // contract.
            const balanceBeneficiaryBefore = await mockERC20.balanceOf(beneficiary);
            await mockServiceNodeRewards.connect(beneficiary).claimRewards();
            const balanceBeneficiaryAfter = await mockERC20.balanceOf(beneficiary);
            expect(balanceBeneficiaryAfter - balanceBeneficiaryBefore).to.equal(50);

            const balanceVestingBefore = await mockERC20.balanceOf(tokenVestingStaking);
            await tokenVestingStaking.connect(beneficiary).claimRewards();
            const balanceVestingAfter = await mockERC20.balanceOf(tokenVestingStaking);

            expect(balanceVestingAfter - balanceVestingBefore).to.equal(STAKING_TEST_AMNT + 50);
        });
    });

    // describe("Multi-contributor functionality", function () {
    //     let contributionContract;
    //     let ownerContribution;

    //     beforeEach(async function () {
    //         // Deploy a new ServiceNodeContribution contract
    //         const tx = await serviceNodeContributionFactory.connect(owner).deployContributionContract([1,2], [3,4,5,6]);
    //         const receipt = await tx.wait();
    //         const event = receipt.logs.find(log => log.fragment.name === "NewServiceNodeContributionContract");
    //         const contributionContractAddress = event.args[0];
    //         contributionContract = await ethers.getContractAt("ServiceNodeContribution", contributionContractAddress);

    //         ownerContribution = await contributionContract.minimumContribution();
    //         await mockERC20.transfer(owner, ownerContribution);
    //         await mockERC20.connect(owner).approve(contributionContract.getAddress(), ownerContribution);
    //         await contributionContract.connect(owner).contributeOperatorFunds(ownerContribution, [3,4,5,6]);
    //     });

    //     it("Should be able to contribute funds to a multi-contributor contract", async function () {
    //         const contributionAmount = await contributionContract.minimumContribution();
    //         await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount);

    //         await expect(tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount))
    //             .to.emit(contributionContract, "NewContribution")
    //             .withArgs(await tokenVestingStaking.getAddress(), contributionAmount);

    //         const contractBalance = await mockERC20.balanceOf(contributionContract.getAddress());
    //         expect(contractBalance).to.equal(ownerContribution + contributionAmount);

    //         const investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
    //         expect(investorServiceNode.deposit).to.equal(contributionAmount);
    //         expect(investorServiceNode.contributionContract).to.equal(await contributionContract.getAddress());

    //         const investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
    //         expect(investorServiceNodesLength).to.equal(1);
    //     });

    //     it("Should be able to withdraw contribution from a multi-contributor contract", async function () {
    //         const contributionAmount = await contributionContract.minimumContribution();
    //         await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount);
    //         await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount);

    //         let investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
    //         expect(investorServiceNodesLength).to.equal(1);

    //         // Simulate time passing to allow withdrawal
    //         await time.increase(24 * 60 * 60 + 1); // 24 hours + 1 second

    //         const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking.getAddress());

    //         await expect(tokenVestingStaking.connect(beneficiary).withdrawContribution(contributionContract.getAddress()))
    //             .to.emit(contributionContract, "WithdrawContribution")
    //             .withArgs(await tokenVestingStaking.getAddress(), contributionAmount);

    //         const balanceAfter = await mockERC20.balanceOf(tokenVestingStaking.getAddress());
    //         expect(balanceAfter).to.equal(balanceBefore + contributionAmount);

    //         investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
    //         expect(investorServiceNodesLength).to.equal(0);
    //     });

    //     it("Should not be able to contribute to an invalid contract", async function () {
    //         const invalidAddress = ethers.Wallet.createRandom().getAddress();
    //         await expect(tokenVestingStaking.connect(beneficiary).contributeFunds(invalidAddress, 1))
    //             .to.be.revertedWith("Invalid contribution contract");
    //     });

    //     it("Should not be able to withdraw from an invalid contract", async function () {
    //         const invalidAddress = ethers.Wallet.createRandom().getAddress();

    //         await expect(tokenVestingStaking.connect(beneficiary).withdrawContribution(invalidAddress))
    //             .to.be.revertedWith("Invalid contribution contract");
    //     });

    //     it("Should update investorServiceNodes correctly on multiple contributions", async function () {
    //         const contributionAmount1 = await contributionContract.minimumContribution();
    //         await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount1);
    //         await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount1);

    //         const contributionAmount2 = await contributionContract.minimumContribution();
    //         await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount2);
    //         await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount2);

    //         const investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
    //         expect(investorServiceNode.deposit).to.equal(contributionAmount1 + contributionAmount2);

    //         let investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
    //         expect(investorServiceNodesLength).to.equal(1);
    //     });

    //     it("Should update investorServiceNodes correctly on when multicontributor node gets filled", async function () {
    //         const contributionAmount1 = await contributionContract.minimumContribution();
    //         await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount1);
    //         await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount1);

    //         const stakingRequirement = await contributionContract.stakingRequirement();
    //         let previousContribution = await contributionContract.totalContribution();

    //         await mockERC20.transfer(anotherContributor, stakingRequirement - previousContribution);
    //         await mockERC20.connect(anotherContributor)
    //                        .approve(contributionContract, stakingRequirement - previousContribution);

    //         await expect(await contributionContract.connect(anotherContributor)
    //                        .contributeFunds(stakingRequirement - previousContribution)).to
    //                        .emit(contributionContract, "Finalized");

    //         // Expect state before the claimRewards to still have the contributionContract details
    //         let investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
    //         expect(investorServiceNodesLength).to.equal(1);
    //         let investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
    //         expect(investorServiceNode.deposit).to.equal(contributionAmount1);
    //         expect(investorServiceNode.contributionContract).to.equal(await contributionContract.getAddress());
    //         expect(investorServiceNode.serviceNodeID).to.equal(0);

    //         await tokenVestingStaking.connect(beneficiary).claimRewards();

    //         // Expect state after the claimRewards to refer to the staking rewards contract itself
    //         investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
    //         expect(investorServiceNodesLength).to.equal(1);
    //         investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
    //         expect(investorServiceNode.deposit).to.equal(contributionAmount1);
    //         expect(investorServiceNode.serviceNodeID).to.equal(1);
    //         expect(investorServiceNode.contributionContract).to.equal(ethers.ZeroAddress);

    //         // Check that the contributors list in the ServiceNodeRewards Contract is correct
    //         const sn = await mockServiceNodeRewards.serviceNodes(1);
    //         const contributorsInRewardsContract = sn.contributors;
    //         expect(contributorsInRewardsContract[0].addr).to.equal(await owner.getAddress());
    //         expect(contributorsInRewardsContract[0].stakedAmount).to.equal(await ownerContribution);
    //         expect(contributorsInRewardsContract[1].addr).to.equal(await tokenVestingStaking.getAddress());
    //         expect(contributorsInRewardsContract[1].stakedAmount).to.equal(await contributionAmount1);
    //         expect(contributorsInRewardsContract[2].addr).to.equal(await anotherContributor.getAddress());
    //         expect(contributorsInRewardsContract[2].stakedAmount).to.equal(await stakingRequirement - previousContribution);



    //     });
    // });
});
