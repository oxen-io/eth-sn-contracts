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
        [owner, beneficiary] = await ethers.getSigners();
        let start = Date.now();
        let end = start + 2 * 365 * 24 * 60 * 60; // + 2 Years

        MockServiceNodeRewards = await ethers.getContractFactory("MockServiceNodeRewards");
        mockServiceNodeRewards = await MockServiceNodeRewards.deploy(mockERC20, STAKING_TEST_AMNT);

        TokenVestingStaking = await ethers.getContractFactory("TokenVestingStaking");
        tokenVestingStaking = await TokenVestingStaking.deploy(beneficiary, owner, start, end, true, mockServiceNodeRewards, mockERC20);

        await mockERC20.transfer(tokenVestingStaking, TEST_AMNT);
        await mockERC20.transfer(mockServiceNodeRewards, TEST_AMNT);
        await time.setNextBlockTimestamp(start + 1);

    });

    it("Should deploy and set the correct revoker", async function () {
        expect(await tokenVestingStaking.revoker()).to.equal(owner.address);
    });

    it("Should deploy and set the correct beneficiary", async function () {
        expect(await tokenVestingStaking.beneficiary()).to.equal(beneficiary.address);
    });

    it("Should be able to stake to a node", async function () {
        const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking);
        await tokenVestingStaking.connect(beneficiary).addBLSPublicKey([0,0],[0,0,0,0],[0,0,0,0]);
        const balanceAfter = await mockERC20.balanceOf(tokenVestingStaking);
        expect(balanceBefore - balanceAfter).to.equal(STAKING_TEST_AMNT);
    });

    it("Should be able to claim rewards", async function () {
        await tokenVestingStaking.connect(beneficiary).addBLSPublicKey([0,0],[0,0,0,0],[0,0,0,0]);
        const balanceBefore = await mockERC20.balanceOf(beneficiary);
        await tokenVestingStaking.connect(beneficiary).claimRewards();
        const balanceAfter = await mockERC20.balanceOf(beneficiary);
        expect(balanceAfter - balanceBefore).to.equal(50);
    });

    it("Should be able to unstake and claim rewards", async function () {
        await tokenVestingStaking.connect(beneficiary).addBLSPublicKey([0,0],[0,0,0,0],[0,0,0,0]);
        const serviceNode = await tokenVestingStaking.serviceNodes(0)
        const balancebeneficiaryBefore = await mockERC20.balanceOf(beneficiary);
        const balanceBefore = await mockERC20.balanceOf(tokenVestingStaking);
        await mockServiceNodeRewards.removeBLSPublicKeyWithSignature(serviceNode.serviceNodeID,0,0,0,0,0,0,[]);
        await tokenVestingStaking.connect(beneficiary).claimRewards();
        const balanceAfter = await mockERC20.balanceOf(tokenVestingStaking);
        const balancebeneficiaryAfter = await mockERC20.balanceOf(beneficiary);
        expect(balancebeneficiaryAfter - balancebeneficiaryBefore).to.equal(50);
        expect(balanceAfter - balanceBefore).to.equal(STAKING_TEST_AMNT);
    });
});
