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
    let vestingContract;
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
        [owner, beneficiary, contributor, anotherContrib] = await ethers.getSigners();

        MockServiceNodeRewards = await ethers.getContractFactory("MockServiceNodeRewards");
        mockServiceNodeRewards = await MockServiceNodeRewards.deploy(mockERC20, STAKING_TEST_AMNT);

        // Deploy ServiceNodeContributionFactory
        ServiceNodeContributionFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
        snContribFactory = await ServiceNodeContributionFactory.deploy(mockServiceNodeRewards.getAddress());

        let start = await time.latest() + 5;
        let end = start + 2 * 365 * 24 * 60 * 60; // + 2 Years
        time.setNextBlockTimestamp(await time.latest() + 4);

        TokenVestingStaking = await ethers.getContractFactory("TokenVestingStaking");
        vestingContract = await TokenVestingStaking.deploy(beneficiary,
                                                               /*revoker*/ owner,
                                                               start,
                                                               end,
                                                               /*transferableBeneficiary*/ true,
                                                               /*rewardsContract*/ mockServiceNodeRewards,
                                                               snContribFactory,
                                                               mockERC20);

        await mockERC20.transfer(vestingContract, TEST_AMNT);
        await mockERC20.transfer(mockServiceNodeRewards, TEST_AMNT);

    });

    it("Should deploy and set the correct revoker", async function () {
        expect(await vestingContract.revoker()).to.equal(await owner.getAddress());
    });

    it("Should deploy and set the correct beneficiary", async function () {
        expect(await vestingContract.beneficiary()).to.equal(await beneficiary.getAddress());
    });

    describe("Add solo node", function () {
        beforeEach(async function () {
            // NOTE: Register a node
            const balanceBefore = await mockERC20.balanceOf(vestingContract);
            const node          = BLS_NODES[0];
            await vestingContract.connect(beneficiary).addBLSPublicKey(node.blsPubkey,
                                                                           node.blsSig,
                                                                           node.snParams,
                                                                           beneficiary);
            const balanceAfter = await mockERC20.balanceOf(vestingContract);
            expect(balanceBefore - balanceAfter).to.equal(STAKING_TEST_AMNT);
        });

        it("Should be able to claim rewards", async function () {
            const balanceBefore = await mockERC20.balanceOf(beneficiary);
            await mockServiceNodeRewards.connect(beneficiary).claimRewards();
            const balanceAfter = await mockERC20.balanceOf(beneficiary);
            expect(balanceAfter - balanceBefore).to.equal(50);

            // NOTE: Expect claim on the investor contract to fail because the node has not had its
            // stake unlocked yet.
            expect(await vestingContract.connect(beneficiary).claimRewards()).to.be.reverted;
        });

        it("Should be able to unstake and claim rewards", async function () {

            const balanceBefore = await mockERC20.balanceOf(vestingContract);
            await mockServiceNodeRewards.removeBLSPublicKeyWithSignature(/*serviceNodeID*/ 1,0,0,0,0,0,0,[]);

            // TODO: The mock adds +50 $SENT everytime we claim, using mocks
            // isn't great because we're not actually testing against the real
            // contract.
            const balanceBeneficiaryBefore = await mockERC20.balanceOf(beneficiary);
            await mockServiceNodeRewards.connect(beneficiary).claimRewards();
            const balanceBeneficiaryAfter = await mockERC20.balanceOf(beneficiary);
            expect(balanceBeneficiaryAfter - balanceBeneficiaryBefore).to.equal(50);

            const balanceVestingBefore = await mockERC20.balanceOf(vestingContract);
            await vestingContract.connect(beneficiary).claimRewards();
            const balanceVestingAfter = await mockERC20.balanceOf(vestingContract);

            expect(balanceVestingAfter - balanceVestingBefore).to.equal(STAKING_TEST_AMNT + 50);
        });
    });

    describe("Multi-contributor functionality", function () {
        let snContribContract;
        let ownerContribAmount;
        let defaultBeneficiaryData;     // Default no-op BeneficiaryData struct

        beforeEach(async function () {
            // NOTE: Deploy a multi-contrib contract w/ operator having funded
            // the min contribution.
            const node = BLS_NODES[0];
            const tx = await snContribFactory.connect(owner)
                                             .deploy(node.blsPubkey,
                                                     node.blsSig,
                                                     node.snParams,
                                                     /*reserved*/ [],
                                                     false /*manualFinalize*/);
            const receipt                  = await tx.wait();
            const event                    = receipt.logs.find(log => log.fragment.name === "NewServiceNodeContributionContract");
            const snContribContractAddress = event.args[0];
            snContribContract              = await ethers.getContractAt("ServiceNodeContribution", snContribContractAddress);

            // NOTE: Setup no-op beneficiary
            defaultBeneficiaryData = {
                setBeneficiary: false,
                beneficiary: owner,
            };

            // NOTE: Operator funds 25% stake
            ownerContribAmount = await snContribContract.minimumContribution();
            await mockERC20.transfer(owner, ownerContribAmount);
            await mockERC20.connect(owner).approve(snContribContract.getAddress(), ownerContribAmount);
            await snContribContract.connect(owner).contributeFunds(ownerContribAmount, defaultBeneficiaryData);
        });

        it("Should be able to contribute funds to a multi-contributor contract", async function () {
            const contribAmount = await snContribContract.minimumContribution();
            await mockERC20.transfer(vestingContract.getAddress(), contribAmount);

            await expect(vestingContract.connect(beneficiary).contributeFunds(snContribContract.getAddress(),
                                                                              contribAmount,
                                                                              /*addrToReceiveRewards*/ beneficiary))
                .to.emit(snContribContract, "NewContribution")
                .withArgs(await vestingContract.getAddress(), contribAmount);

            const contractBalance = await mockERC20.balanceOf(snContribContract.getAddress());
            expect(contractBalance).to.equal(ownerContribAmount + contribAmount);

            // NOTE: Verify contrib contract state
            // NOTE: getContributions returns struct-of-arrays (stakers[], beneficiaries[], contributions[])
            await expect(await snContribContract.getContributions()).to.deep.equal(
                [
                                       /*Operator*/        /*Investor*/
                    /*Stakers*/       [owner.address,      await vestingContract.getAddress()],
                    /*Beneficiaries*/ [owner.address,      beneficiary.address],
                    /*Contributions*/ [ownerContribAmount, contribAmount],
                ]
            );
        });

        it("Should be able to withdraw contribution from a multi-contributor contract", async function () {
            const contribAmount = await snContribContract.minimumContribution();
            await mockERC20.transfer(vestingContract.getAddress(), contribAmount);
            await vestingContract.connect(beneficiary).contributeFunds(snContribContract.getAddress(),
                                                                       contribAmount,
                                                                       /*addrToReceiveRewards*/ beneficiary);

            // NOTE: Simulate time passing to allow withdrawal
            await time.increase(24 * 60 * 60 + 1); // 24 hours + 1 second
            const balanceBefore = await mockERC20.balanceOf(vestingContract.getAddress());

            // NOTE: Withdraw
            await expect(vestingContract.connect(beneficiary).withdrawContribution(snContribContract.getAddress()))
                .to.emit(snContribContract, "WithdrawContribution")
                .withArgs(await vestingContract.getAddress(), contribAmount);

            // NOTE: Verify funds went back to vesting contract
            const balanceAfter = await mockERC20.balanceOf(vestingContract.getAddress());
            expect(balanceAfter).to.equal(balanceBefore + contribAmount);

            // NOTE: Verify contrib contract state
            await expect(await snContribContract.getContributions()).to.deep.equal(
                [
                                       /*Operator*/
                    /*Stakers*/       [owner.address],
                    /*Beneficiaries*/ [owner.address],
                    /*Contributions*/ [ownerContribAmount]
                ]
            );
        });

        it("Should not be able to contribute to an invalid contract", async function () {
            const contribAmount  = await snContribContract.minimumContribution();
            const invalidAddress = ethers.Wallet.createRandom().getAddress();
            await expect(vestingContract.connect(beneficiary).contributeFunds(invalidAddress,
                                                                              contribAmount,
                                                                              /*addrToReceiveRewards*/ beneficiary))
                .to.be.revertedWith("Contract address is not a valid multi-contributor SN contract");
        });

        it("Should not be able set beneficiary to zero address", async function () {
            const contribAmount  = await snContribContract.minimumContribution();
            const invalidAddress = ethers.Wallet.createRandom().getAddress();
            const zeroAddress    = "0x0000000000000000000000000000000000000000";
            await expect(vestingContract.connect(beneficiary).contributeFunds(invalidAddress,
                                                                              contribAmount,
                                                                              /*addrToReceiveRewards*/ zeroAddress))
                .to.be.revertedWith("Rewards can not be paid to the zero-address");
        });


        it("Should not be able to withdraw from an invalid contract", async function () {
            const invalidAddress = ethers.Wallet.createRandom().getAddress();
            await expect(vestingContract.connect(beneficiary).withdrawContribution(invalidAddress))
                .to.be.revertedWith("Contract address is not a valid multi-contributor SN contract");
        });

        it("Handles multiple contributions to same contract", async function () {
            const contribAmount1 = await snContribContract.minimumContribution();
            await mockERC20.transfer(vestingContract.getAddress(), contribAmount1);
            await vestingContract.connect(beneficiary).contributeFunds(snContribContract.getAddress(),
                                                                       contribAmount1,
                                                                       /*addrToReceiveRewards*/ beneficiary);

            const contribAmount2 = await snContribContract.minimumContribution();
            await mockERC20.transfer(vestingContract.getAddress(), contribAmount2);
            await vestingContract.connect(beneficiary).contributeFunds(snContribContract.getAddress(),
                                                                       contribAmount2,
                                                                       /*addrToReceiveRewards*/ beneficiary);

            // NOTE: Verify contrib contract state
            // NOTE: getContributions returns struct-of-arrays (stakers[], beneficiaries[], contributions[])
            await expect(await snContribContract.getContributions()).to.deep.equal(
                [
                                       /*Operator*/        /*Investor*/
                    /*Stakers*/       [owner.address,      await vestingContract.getAddress()],
                    /*Beneficiaries*/ [owner.address,      beneficiary.address],
                    /*Contributions*/ [ownerContribAmount, contribAmount1 + contribAmount2],
                ]
            );
        });

        it("Handles update to beneficiary", async function () {
            const contribAmount1 = await snContribContract.minimumContribution();
            await mockERC20.transfer(vestingContract.getAddress(), contribAmount1);
            await vestingContract.connect(beneficiary).contributeFunds(snContribContract.getAddress(),
                                                                       contribAmount1,
                                                                       /*addrToReceiveRewards*/ beneficiary);

            // NOTE: Update beneficiary of the investor to the owner.
            await vestingContract.connect(beneficiary).updateBeneficiary(snContribContract.getAddress(),
                                                                         owner);

            // NOTE: Verify contrib contract state
            // NOTE: getContributions returns struct-of-arrays (stakers[], beneficiaries[], contributions[])
            await expect(await snContribContract.getContributions()).to.deep.equal(
                [
                                       /*Operator*/        /*Investor*/
                    /*Stakers*/       [owner.address,      await vestingContract.getAddress()],
                    /*Beneficiaries*/ [owner.address,      owner.address],
                    /*Contributions*/ [ownerContribAmount, contribAmount1],
                ]
            );
        });

        it("Should receive rewards after multi-contrib node is registered", async function () {
            // NOTE: Investor contributes funds to the contribution contract
            const contribAmount1 = await snContribContract.minimumContribution();
            await mockERC20.transfer(vestingContract.getAddress(), contribAmount1);
            await vestingContract.connect(beneficiary).contributeFunds(snContribContract.getAddress(),
                                                                       contribAmount1,
                                                                       /*addrToReceiveRewards*/ beneficiary);


            // NOTE: Fund the contract with another contributor
            const stakingRequirement = await snContribContract.stakingRequirement();
            let previousContribution = await snContribContract.totalContribution();
            const anotherContribAmount = stakingRequirement - previousContribution;

            await mockERC20.transfer(anotherContrib, anotherContribAmount);
            await mockERC20.connect(anotherContrib)
                           .approve(snContribContract, anotherContribAmount);

            await expect(await snContribContract.connect(anotherContrib)
                           .contributeFunds(anotherContribAmount, defaultBeneficiaryData)).to
                           .emit(snContribContract, "Finalized");

            // NOTE: Verify contrib contract state
            // NOTE: getContributions returns struct-of-arrays (stakers[], beneficiaries[], contributions[])
            await expect(await snContribContract.getContributions()).to.deep.equal(
                [
                                       /*Operator*/        /*Investor*/                        /*Another Contributor*/
                    /*Stakers*/       [owner.address,      await vestingContract.getAddress(), anotherContrib.address],
                    /*Beneficiaries*/ [owner.address,      beneficiary.address,                anotherContrib.address],
                    /*Contributions*/ [ownerContribAmount, contribAmount1,                     anotherContribAmount],
                ]
            );

            // NOTE: Claim should fail because node is not unlocked.
            expect(await vestingContract.connect(beneficiary).claimRewards()).to.be.reverted;

            // NOTE: Claim rewards by the beneficiary from the rewards contract
            const balanceBeneficiaryBefore = await mockERC20.balanceOf(beneficiary);
            await mockServiceNodeRewards.connect(beneficiary).claimRewards();
            const balanceBeneficiaryAfter = await mockERC20.balanceOf(beneficiary);

            // Check that the contributors list in the ServiceNodeRewards Contract is correct
            const sn = await mockServiceNodeRewards.serviceNodes(1);
            const contributorsInRewardsContract = sn.contributors;

            expect(contributorsInRewardsContract[0].staker.addr)       .to.equal(await owner.getAddress());
            expect(contributorsInRewardsContract[0].staker.beneficiary).to.equal(await owner.getAddress());
            expect(contributorsInRewardsContract[0].stakedAmount)      .to.equal(ownerContribAmount);

            expect(contributorsInRewardsContract[1].staker.addr)       .to.equal(await vestingContract.getAddress());
            expect(contributorsInRewardsContract[1].staker.beneficiary).to.equal(await beneficiary.getAddress());
            expect(contributorsInRewardsContract[1].stakedAmount)      .to.equal(contribAmount1);

            expect(contributorsInRewardsContract[2].staker.addr)       .to.equal(await anotherContrib.getAddress());
            expect(contributorsInRewardsContract[2].staker.beneficiary).to.equal(await anotherContrib.getAddress());
            expect(contributorsInRewardsContract[2].stakedAmount)      .to.equal(anotherContribAmount);
        });
    });
});
