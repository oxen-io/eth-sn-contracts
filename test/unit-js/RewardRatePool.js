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
            mockERC20 = await MockERC20.deploy("SENT Token", "SENT", 9);
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
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let last_paid = await rewardRatePool.lastPaidOutTime();
        await expect(await rewardRatePool.calculateReleasedAmount(last_paid + BigInt(seconds_in_year)))
            .to.equal(ethers.parseUnits((principal * 0.151).toFixed(0).toString(), 9));
    });
    
    it("should calculate 15.1% released correctly", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let last_paid = await rewardRatePool.lastPaidOutTime();
        await expect(await rewardRatePool.calculateReleasedAmount(last_paid))
            .to.equal(0);
    });

    it("should calculate reward rate", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        let last_paid = await rewardRatePool.lastPaidOutTime();
        await expect(await rewardRatePool.rewardRate(last_paid))
            .to.equal(ethers.parseUnits((principal * 0.151).toFixed().toString(), 9) * BigInt(seconds_in_2_minutes) / BigInt(seconds_in_year));
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
        await expect(await rewardRatePool.calculateReleasedAmount(t))
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
        await expect(await rewardRatePool.calculateReleasedAmount(t))
            .to.equal(bigAtomicPrincipal * BigInt("14097571610714") / BigInt("100000000000000"));
    });

    it("should be able to release funds to the rewards contract", async function () {
        await mockERC20.transfer(rewardRatePool, bigAtomicPrincipal);
        expect(await mockERC20.balanceOf(rewardRatePool)).to.equal(bigAtomicPrincipal);

        // NOTE: Advance time and test the payout release
        let last_paid    = await rewardRatePool.lastPaidOutTime();
        let total_payout = await rewardRatePool.calculateReleasedAmount(last_paid + BigInt(seconds_in_year));

        await time.setNextBlockTimestamp(last_paid + BigInt(seconds_in_year));
        await expect(await rewardRatePool.payoutReleased()).to
                                                           .emit(rewardRatePool, 'FundsReleased')
                                                           .withArgs(total_payout);

        expect(await mockERC20.balanceOf(serviceNodeRewards)).to
                                                             .equal(total_payout);


        // NOTE: Advance time again and test the payout release
        last_paid             = await rewardRatePool.lastPaidOutTime();
        let next_total_payout = await rewardRatePool.calculateReleasedAmount(last_paid + BigInt(seconds_in_year));
        total_payout          = next_total_payout - total_payout;

        await time.setNextBlockTimestamp(last_paid + BigInt(seconds_in_year));
        await expect(await rewardRatePool.payoutReleased()).to
                                                           .emit(rewardRatePool, 'FundsReleased')
                                                           .withArgs(total_payout);

        expect(await mockERC20.balanceOf(serviceNodeRewards)).to
                                                             .equal(next_total_payout);
    });
});
