const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const STAKING_TEST_AMNT = 15000000000000

describe("RewardRatePool Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let ServiceNodeRewards;
    let serviceNodeRewards;
    let RewardRatePool;
    let rewardRatePool;
    let principal = 100000;
    let bigAtomicPrincipal = ethers.parseUnits(principal.toString(), 9);
    let seconds_in_year = 365*24*60*60;
    let seconds_in_2_minutes = 2*60;

    beforeEach(async function () {
        // Deploy a mock ERC20 token
        try {
            // Deploy a mock ERC20 token
            MockERC20 = await ethers.getContractFactory("MockERC20");
            mockERC20 = await MockERC20.deploy("SENT Token", "SENT", 9);
        } catch (error) {
            console.error("Error deploying MockERC20:", error);
        }

        ServiceNodeRewards = await ethers.getContractFactory("MockServiceNodeRewards");
        serviceNodeRewards = await ServiceNodeRewards.deploy(mockERC20, STAKING_TEST_AMNT);

        RewardRatePool = await ethers.getContractFactory("RewardRatePool");
        rewardRatePool = await RewardRatePool.deploy(serviceNodeRewards, mockERC20);
    });

    it("Should have the correct interest rate", async function () {
        await expect(await rewardRatePool.ANNUAL_INTEREST_RATE())
            .to.equal(145);
    });

    it("should calculate 14.5% interest correctly", async function () {
        await expect(await rewardRatePool.calculateInterestAmount(principal, seconds_in_year))
            .to.equal((principal * 0.145).toFixed(0));
    });

    it("should calculate 14.5% released correctly", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let last_paid = await rewardRatePool.lastPaidOutTime();
        await expect(await rewardRatePool.calculateReleasedAmount(last_paid + BigInt(seconds_in_year)))
            .to.equal(ethers.parseUnits((principal * 0.145).toFixed(0).toString(), 9));
    });
    
    it("should calculate 14.5% released correctly", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let last_paid = await rewardRatePool.lastPaidOutTime();
        await expect(await rewardRatePool.calculateReleasedAmount(last_paid))
            .to.equal(0);
    });

    it("should calculate reward rate", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let last_paid = await rewardRatePool.lastPaidOutTime();
        await expect(await rewardRatePool.rewardRate(last_paid))
            .to.equal(ethers.parseUnits((principal * 0.145).toFixed().toString(), 9) * BigInt(seconds_in_2_minutes) / BigInt(seconds_in_year));
    });

    it("should be able to release funds to the rewards contract", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        expect(await mockERC20.balanceOf(rewardRatePool)).to.equal(bigAtomicPrincipal);
        let last_paid = await rewardRatePool.lastPaidOutTime();
        let expected_removed = await rewardRatePool.calculateReleasedAmount(last_paid + BigInt(seconds_in_year));
        await time.setNextBlockTimestamp(last_paid + BigInt(seconds_in_year));
        await expect(await rewardRatePool.payoutReleased())
            .to.emit(rewardRatePool, 'FundsReleased')
            .withArgs(expected_removed);
        expect(await mockERC20.balanceOf(serviceNodeRewards)).to.equal(expected_removed);
    });
});