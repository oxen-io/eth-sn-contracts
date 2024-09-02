const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT = 50000000000000

describe("TokenVestingStaking Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let MockServiceNodeRewards;
    let mockServiceNodeRewards;
    let TokenVestingStaking;
    let tokenVestingStaking;
    let owner;

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
        tokenVestingStaking = await TokenVestingStaking.deploy(beneficiary, owner, start, end, true, mockServiceNodeRewards, serviceNodeContributionFactory, mockERC20);

        await mockERC20.transfer(tokenVestingStaking, TEST_AMNT);
        await mockERC20.transfer(mockServiceNodeRewards, TEST_AMNT);

    });

    it("Should deploy and set the correct revoker", async function () {
        expect(await tokenVestingStaking.revoker()).to.equal(await owner.getAddress());
    });

    it("Should deploy and set the correct beneficiary", async function () {
        expect(await tokenVestingStaking.beneficiary()).to.equal(await beneficiary.getAddress());
    });

    it("Should be able to stake to a node", async function () {
        const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking);
        await tokenVestingStaking.connect(beneficiary).addBLSPublicKey([0,0],[0,0,0,0],[0,0,0,0]);
        const balanceAfter = await mockERC20.balanceOf(tokenVestingStaking);
        expect(balanceBefore - balanceAfter).to.equal(STAKING_TEST_AMNT);
    });

    it("Should be able to claim rewards", async function () {
        await tokenVestingStaking.connect(beneficiary).addBLSPublicKey([0,0],[0,0,0,0],[0,0,0,0]);
        let node = await mockServiceNodeRewards.serviceNodes(1);
        const balanceBefore = await mockERC20.balanceOf(beneficiary);
        await tokenVestingStaking.connect(beneficiary).claimRewards();
        const balanceAfter = await mockERC20.balanceOf(beneficiary);
        expect(balanceAfter - balanceBefore).to.equal(50);
    });

    it("Should be able to unstake and claim rewards", async function () {
        await tokenVestingStaking.connect(beneficiary).addBLSPublicKey([0,0],[0,0,0,0],[0,0,0,0]);
        const serviceNode = await tokenVestingStaking.investorServiceNodes(0)
        const balancebeneficiaryBefore = await mockERC20.balanceOf(beneficiary);
        const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking);
        await mockServiceNodeRewards.removeBLSPublicKeyWithSignature(serviceNode.serviceNodeID,0,0,0,0,0,0,[]);
        await tokenVestingStaking.connect(beneficiary).claimRewards();
        const balanceAfter = await mockERC20.balanceOf(tokenVestingStaking);
        const balancebeneficiaryAfter = await mockERC20.balanceOf(beneficiary);
        expect(balancebeneficiaryAfter - balancebeneficiaryBefore).to.equal(50);
        expect(balanceAfter - balanceBefore).to.equal(STAKING_TEST_AMNT);
    });

    describe("Multi-contributor functionality", function () {
        let contributionContract;
        let ownerContribution;

        beforeEach(async function () {
            // Deploy a new ServiceNodeContribution contract
            const tx = await serviceNodeContributionFactory.connect(owner).deployContributionContract([1,2], [3,4,5,6]);
            const receipt = await tx.wait();
            const event = receipt.logs.find(log => log.fragment.name === "NewServiceNodeContributionContract");
            const contributionContractAddress = event.args[0];
            contributionContract = await ethers.getContractAt("ServiceNodeContribution", contributionContractAddress);

            ownerContribution = await contributionContract.minimumContribution();
            await mockERC20.transfer(owner, ownerContribution);
            await mockERC20.connect(owner).approve(contributionContract.getAddress(), ownerContribution);
            await contributionContract.connect(owner).contributeOperatorFunds(ownerContribution, [3,4,5,6]);
        });

        it("Should be able to contribute funds to a multi-contributor contract", async function () {
            const contributionAmount = await contributionContract.minimumContribution();
            await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount);

            await expect(tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount))
                .to.emit(contributionContract, "NewContribution")
                .withArgs(await tokenVestingStaking.getAddress(), contributionAmount);

            const contractBalance = await mockERC20.balanceOf(contributionContract.getAddress());
            expect(contractBalance).to.equal(ownerContribution + contributionAmount);

            const investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
            expect(investorServiceNode.deposit).to.equal(contributionAmount);
            expect(investorServiceNode.contributionContract).to.equal(await contributionContract.getAddress());

            const investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
            expect(investorServiceNodesLength).to.equal(1);
        });

        it("Should be able to withdraw contribution from a multi-contributor contract", async function () {
            const contributionAmount = await contributionContract.minimumContribution();
            await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount);
            await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount);

            let investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
            expect(investorServiceNodesLength).to.equal(1);

            // Simulate time passing to allow withdrawal
            await time.increase(24 * 60 * 60 + 1); // 24 hours + 1 second

            const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking.getAddress());

            await expect(tokenVestingStaking.connect(beneficiary).withdrawContribution(contributionContract.getAddress()))
                .to.emit(contributionContract, "WithdrawContribution")
                .withArgs(await tokenVestingStaking.getAddress(), contributionAmount);

            const balanceAfter = await mockERC20.balanceOf(tokenVestingStaking.getAddress());
            expect(balanceAfter).to.equal(balanceBefore + contributionAmount);

            investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
            expect(investorServiceNodesLength).to.equal(0);
        });

        it("Should not be able to contribute to an invalid contract", async function () {
            const invalidAddress = ethers.Wallet.createRandom().getAddress();
            await expect(tokenVestingStaking.connect(beneficiary).contributeFunds(invalidAddress, 1))
                .to.be.revertedWith("Invalid contribution contract");
        });

        it("Should not be able to withdraw from an invalid contract", async function () {
            const invalidAddress = ethers.Wallet.createRandom().getAddress();

            await expect(tokenVestingStaking.connect(beneficiary).withdrawContribution(invalidAddress))
                .to.be.revertedWith("Invalid contribution contract");
        });

        it("Should update investorServiceNodes correctly on multiple contributions", async function () {
            const contributionAmount1 = await contributionContract.minimumContribution();
            await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount1);
            await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount1);

            const contributionAmount2 = await contributionContract.minimumContribution();
            await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount2);
            await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount2);

            const investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
            expect(investorServiceNode.deposit).to.equal(contributionAmount1 + contributionAmount2);

            let investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
            expect(investorServiceNodesLength).to.equal(1);
        });

        it("Should update investorServiceNodes correctly on when multicontributor node gets filled", async function () {
            const contributionAmount1 = await contributionContract.minimumContribution();
            await mockERC20.transfer(tokenVestingStaking.getAddress(), contributionAmount1);
            await tokenVestingStaking.connect(beneficiary).contributeFunds(contributionContract.getAddress(), contributionAmount1);

            const stakingRequirement = await contributionContract.stakingRequirement();
            let previousContribution = await contributionContract.totalContribution();

            await mockERC20.transfer(anotherContributor, stakingRequirement - previousContribution);
            await mockERC20.connect(anotherContributor)
                           .approve(contributionContract, stakingRequirement - previousContribution);

            await expect(await contributionContract.connect(anotherContributor)
                           .contributeFunds(stakingRequirement - previousContribution)).to
                           .emit(contributionContract, "Finalized");

            // Expect state before the claimRewards to still have the contributionContract details
            let investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
            expect(investorServiceNodesLength).to.equal(1);
            let investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
            expect(investorServiceNode.deposit).to.equal(contributionAmount1);
            expect(investorServiceNode.contributionContract).to.equal(await contributionContract.getAddress());
            expect(investorServiceNode.serviceNodeID).to.equal(0);

            await tokenVestingStaking.connect(beneficiary).claimRewards();

            // Expect state after the claimRewards to refer to the staking rewards contract itself
            investorServiceNodesLength = await tokenVestingStaking.investorServiceNodesLength();
            expect(investorServiceNodesLength).to.equal(1);
            investorServiceNode = await tokenVestingStaking.investorServiceNodes(0);
            expect(investorServiceNode.deposit).to.equal(contributionAmount1);
            expect(investorServiceNode.serviceNodeID).to.equal(1);
            expect(investorServiceNode.contributionContract).to.equal(ethers.ZeroAddress);

            // Check that the contributors list in the ServiceNodeRewards Contract is correct
            const sn = await mockServiceNodeRewards.serviceNodes(1);
            const contributorsInRewardsContract = sn.contributors;
            expect(contributorsInRewardsContract[0].addr).to.equal(await owner.getAddress());
            expect(contributorsInRewardsContract[0].stakedAmount).to.equal(await ownerContribution);
            expect(contributorsInRewardsContract[1].addr).to.equal(await tokenVestingStaking.getAddress());
            expect(contributorsInRewardsContract[1].stakedAmount).to.equal(await contributionAmount1);
            expect(contributorsInRewardsContract[2].addr).to.equal(await anotherContributor.getAddress());
            expect(contributorsInRewardsContract[2].stakedAmount).to.equal(await stakingRequirement - previousContribution);



        });
    });
});
