const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const STAKING_TEST_AMNT = 15000000000000

describe("RewardRatePool Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let ServiceNodeRewards;
    let serviceNodeRewards;
    let RewardRatePool;
    let rewardRatePool;
    const principal = 100000;
    const bigAtomicPrincipal = ethers.parseUnits(principal.toString(), 9);
    const seconds_in_day = 24*60*60;
    const seconds_in_year = 365 * seconds_in_day;
    const seconds_in_2_minutes = 2*60;

    beforeEach(async function () {
        // Deploy a mock ERC20 token
        try {
            // Deploy a mock ERC20 token
            MockERC20 = await ethers.getContractFactory("MockERC20");
            mockERC20 = await MockERC20.deploy("SESH Token", "SESH", 240_000_000n * 1_000_000_000n);
        } catch (error) {
            console.error("Error deploying MockERC20:", error);
        }

        ServiceNodeRewards = await ethers.getContractFactory("MockServiceNodeRewards");
        serviceNodeRewards = await ServiceNodeRewards.deploy(mockERC20, STAKING_TEST_AMNT);

        // NOTE: Set the serviceNodeRewards contract as the recipient of rewards
        RewardRatePool = await ethers.getContractFactory("RewardRatePool");
        rewardRatePool = await upgrades.deployProxy(RewardRatePool, [await serviceNodeRewards.getAddress(), await mockERC20.getAddress()]);
    });

    it("Should have the correct payout rate", async function () {
        await expect(await rewardRatePool.ANNUAL_SIMPLE_PAYOUT_RATE())
            .to.equal(151);
    });

    it("should calculate 15.1% payout correctly", async function () {
        await expect(await rewardRatePool.calculatePayoutAmount(principal, seconds_in_year))
            .to.equal((principal * 0.151).toFixed(0));
    });

    it("should calculate 15.1% released correctly", async function () {
        await time.setNextBlockTimestamp(await time.latest() + 42)
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        await expect(await rewardRatePool.calculateReleasedAmount())
            // Block timestamp has advanced by 42 seconds, so there will be a corresponding released amount:
            .to.equal(ethers.parseUnits((principal * 0.151).toFixed().toString(), 9) * BigInt(42) / BigInt(seconds_in_year));
    });

    it("should calculate reward rate", async function () {
        await time.setNextBlockTimestamp(await time.latest() + 1)
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        // The -1 here is because the block time advances by at least 1, and that's enough to just
        // slightly reduce our reward by one atomic unit with the specific values we use here.
        await expect(await rewardRatePool.rewardRate())
            .to.equal(ethers.parseUnits((principal * 0.151).toFixed().toString(), 9) * BigInt(seconds_in_2_minutes) / BigInt(seconds_in_year) - BigInt(1));
    });

    it("should should be ~14.017% with daily withdrawals", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let t = await rewardRatePool.lastPaidOutTime();
        let total_paid = 0;
        for (let i = 0; i < 365; i++) {
            t += BigInt(seconds_in_day);
            await time.setNextBlockTimestamp(t);
            await rewardRatePool.payoutReleased();
        }
        await expect(await rewardRatePool.calculateReleasedAmount())
            .to.equal(bigAtomicPrincipal * BigInt("14017916502388") / BigInt("100000000000000"));
    });

    it("should should be ~14.098% with monthly withdrawals", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let t = await rewardRatePool.lastPaidOutTime();
        let total_paid = 0;
        for (let i = 0; i < 12; i++) {
            t += BigInt(seconds_in_year / 12);
            await time.setNextBlockTimestamp(t);
            await rewardRatePool.payoutReleased();
        }
        await expect(await rewardRatePool.calculateReleasedAmount())
            .to.equal(bigAtomicPrincipal * BigInt("14097571610714") / BigInt("100000000000000"));
    });

    it("should be able to release funds to the rewards contract", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        expect(await mockERC20.balanceOf(rewardRatePool)).to.equal(bigAtomicPrincipal);

        // NOTE: Advance time and test the payout release
        let last_paid = await rewardRatePool.lastPaidOutTime();
        await time.setNextBlockTimestamp(last_paid + BigInt(seconds_in_year));
        await expect(await rewardRatePool.payoutReleased()).to
                                                           .emit(rewardRatePool, 'FundsReleased')
                                                           .withArgs(15100000000000);

        // NOTE: Advance time again and test the payout release
        last_paid = await rewardRatePool.lastPaidOutTime();
        await time.setNextBlockTimestamp(last_paid + BigInt(seconds_in_year));
        await expect(await rewardRatePool.payoutReleased()).to
                                                           .emit(rewardRatePool, 'FundsReleased')
                                                           .withArgs(12819900000000); // (10000 - 15.1%) * 15.1%
    });
});
