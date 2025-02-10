const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

async function verifySeedData(contractSN, seedEntry) {
    expect(contractSN.blsPubkey[0]).to.equal(BigInt(seedEntry.blsPubkey.X));
    expect(contractSN.blsPubkey[1]).to.equal(BigInt(seedEntry.blsPubkey.Y));
    expect(contractSN.deposit).to.equal(BigInt(seedEntry.deposit));
    expect(contractSN.contributors.length).to.equal(seedEntry.contributors.length);
    for (let contributorIndex = 0; contributorIndex < contractSN.contributors.length; contributorIndex++) {
        expect(BigInt(contractSN.contributors[0].addr)).to.equal(BigInt(seedEntry.contributors[contributorIndex].addr));
        expect(contractSN.contributors[0].stakedAmount).to.equal(seedEntry.contributors[contributorIndex].stakedAmount);
    }
}

describe("TestnetServiceNodeRewards Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let ServiceNodeRewards;
    let serviceNodeRewards;
    let owner;
    let foundationPool;

    const staking_req = 120000000000n;

    beforeEach(async function () {
        // Deploy a mock ERC20 token
        try {
            // Deploy a mock ERC20 token
            MockERC20 = await ethers.getContractFactory("MockERC20");
            mockERC20 = await MockERC20.deploy("SESH Token", "SESH", 240_000_000n * 1_000_000_000n);
        } catch (error) {
            console.error("Error deploying MockERC20:", error);
        }

        // Get signers
        [owner, foundationPool] = await ethers.getSigners();

        ServiceNodeRewardsMaster = await ethers.getContractFactory("TestnetServiceNodeRewards");
        serviceNodeRewards = await upgrades.deployProxy(ServiceNodeRewardsMaster,
            [ await mockERC20.getAddress(),    // token address
            await foundationPool.getAddress(), // foundation pool address
            staking_req,                       // testnet staking requirement
            10,                                // max contributors
            1,                                 // liquidator reward ratio
            1,                                 // pool share of liquidation ratio
            8                                  // recipient ratio
            ]);
    });

    it("Seed and test the admin exit", async function () {
        let ed25519_generator = 1n;
        const seedData = [
            {
                blsPubkey: {
                    X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                    Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                },
                ed25519Pubkey: ed25519_generator++,
                addedTimestamp: Math.floor(new Date().getTime() / 1000),
                contributors: [
                    {
                        staker: {
                            addr:        "0x66d801a70615979d82c304b7db374d11c232db66",
                            beneficiary: "0x66d801a70615979d82c304b7db374d11c232db66",
                        },
                        stakedAmount: staking_req,
                    }
                ]
            },
        ];

        await serviceNodeRewards.connect(owner).seedPublicKeyList(seedData);
        expect(await serviceNodeRewards.totalNodes()).to.equal(1);
        let aggregate_pubkey = await serviceNodeRewards.aggregatePubkey();
        expect(aggregate_pubkey[0]).to.equal(seedData[0].blsPubkey.X);
        expect(aggregate_pubkey[1]).to.equal(seedData[0].blsPubkey.Y);
        verifySeedData(await serviceNodeRewards.serviceNodes(1), seedData[0]);
        await serviceNodeRewards.connect(owner).start();

        await serviceNodeRewards.connect(owner).requestExitNodeBySNID([1])
        await serviceNodeRewards.connect(owner).exitNodeBySNID([1])
        expect(await serviceNodeRewards.totalNodes()).to.equal(0);
    });
});

