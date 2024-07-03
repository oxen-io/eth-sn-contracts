const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

async function verifySeedData(contractSN, seedEntry) {
    expect(contractSN.pubkey[0]).to.equal(BigInt(seedEntry.pubkey.X));
    expect(contractSN.pubkey[1]).to.equal(BigInt(seedEntry.pubkey.Y));
    expect(contractSN.deposit).to.equal(BigInt(seedEntry.deposit));
    expect(contractSN.contributors.length).to.equal(seedEntry.contributors.length);
    for (let contributorIndex = 0; contributorIndex < contractSN.contributors.length; contributorIndex++) {
        expect(BigInt(contractSN.contributors[0].addr)).to.equal(BigInt(seedEntry.contributors[contributorIndex].addr));
        expect(contractSN.contributors[0].stakedAmount).to.equal(seedEntry.contributors[contributorIndex].stakedAmount);
    }
}

describe("ServiceNodeRewards Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let ServiceNodeRewards;
    let serviceNodeRewards;
    let owner;
    let foundationPool;

    beforeEach(async function () {
        // Deploy a mock ERC20 token
        try {
            // Deploy a mock ERC20 token
            MockERC20 = await ethers.getContractFactory("MockERC20");
            mockERC20 = await MockERC20.deploy("SENT Token", "SENT", 18);
        } catch (error) {
            console.error("Error deploying MockERC20:", error);
        }

        // Get signers
        [owner, foundationPool] = await ethers.getSigners();

        ServiceNodeRewardsMaster = await ethers.getContractFactory("ServiceNodeRewards");
        serviceNodeRewards = await upgrades.deployProxy(ServiceNodeRewardsMaster, 
            [ await mockERC20.getAddress(),              // token address
            await foundationPool.getAddress(),         // foundation pool address
            15000,                          // staking requirement
            10,                             // max contributors
            0,                              // liquidator reward ratio
            0,                              // pool share of liquidation ratio
            1                               // recipient ratio
            ]);
    });

    it("Should deploy and set the correct owner", async function () {
        expect(await serviceNodeRewards.owner()).to.equal(owner.address);
    });

    it("Should have zero service nodes", async function () {
        expect(await serviceNodeRewards.serviceNodesLength()).to.equal(0);
    });

    describe("Seeding the public key as owner", function () {

        it("Should correctly seed public key list with a single item", async function () {
            const seedData = [
                {
                    pubkey: {
                        X: "0x0b5e634d0407c021e9e9dd9d03c4965810e236fef0955ab345e1d049a0438ec6",
                        Y: "0x1dbb7bf2b1f5340d4b5c466a0641b00cd3a9d9588c7bcad1c3158bdcc65c3332",
                    },
                    deposit: 1000,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 1000,
                        }
                    ]
                },
            ];

            await serviceNodeRewards.connect(owner).seedPublicKeyList(seedData);
            expect(await serviceNodeRewards.serviceNodesLength()).to.equal(1);
            let aggregate_pubkey = await serviceNodeRewards.aggregatePubkey();
            expect(aggregate_pubkey[0] == seedData[0].pubkey.X)
            expect(aggregate_pubkey[1] == seedData[0].pubkey.Y)
            verifySeedData(await serviceNodeRewards.serviceNodes(1), seedData[0]);
        });

        it("Should correctly seed public key list with multiple items", async function () {
            const seedData = [
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 2000,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 2000,
                        }
                    ]
                },
                {
                    pubkey: {
                        X: "0x2ef6b73ab4486484de80681753a6a90c6a88a71f60aace9520fe6bb8bb8de34e",
                        Y: "0x29b8f2a87a758a89c394b121298b946dce9ada3226b5d008e54e54ddcd9e5227",
                    },
                    deposit: 2000,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 2000,
                        }
                    ]
                },
            ];

            await serviceNodeRewards.connect(owner).seedPublicKeyList(seedData);
            let expected_aggregate_pubkey = [
                BigInt("0x040a638a13320ea807115f1e7865c89c70d2d3df83e2e8c3eaea519e18b6e6b0"),
                BigInt("0x019081a4475388be53e1088f6ec0dd79f99fc794709b9cf8b1ad401a9c4d3413"),
            ];
            let aggregate_pubkey = await serviceNodeRewards.aggregatePubkey();
            expect(aggregate_pubkey[0] == expected_aggregate_pubkey[0])
            expect(aggregate_pubkey[1] == expected_aggregate_pubkey[1])

            // NOTE: We know that the sentinel node is reserved at the 0th ID.
            // Hence the 2 service nodes we added are at ID 1 and 2.
            expect(await serviceNodeRewards.serviceNodesLength()).to.equal(2);
            verifySeedData(await serviceNodeRewards.serviceNodes(1), seedData[0]);
            verifySeedData(await serviceNodeRewards.serviceNodes(2), seedData[1]);
        });

        it("Should fail to seed public key list with duplicate items", async function () {
            const seedData = [
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 1000,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 1000,
                        }
                    ]
                },
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 1000,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 1000,
                        }
                    ]
                },
            ];

            await expect(serviceNodeRewards.connect(owner).seedPublicKeyList(seedData))
                .to.be.revertedWithCustomError(serviceNodeRewards, "BLSPubkeyAlreadyExists")
        });

        it("Fails when sum of contributor stakes do not add up the deposit amount", async function () {
            const seedData = [
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 1000,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 500,
                        }
                    ]
                },
            ];

            await expect(serviceNodeRewards.connect(owner).seedPublicKeyList(seedData)).to.be.reverted;
        });

        it("Fails if deposit is 0", async function () {
            const seedData = [
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 0,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 1000,
                        }
                    ]
                },
            ];

            await expect(serviceNodeRewards.connect(owner).seedPublicKeyList(seedData)).to.be.reverted;
        });

        it("Fails if the BLS pubkey is the zero key", async function () {
            const seedData = [
                {
                    pubkey: {
                        X: "0x0000000000000000000000000000000000000000000000000000000000000000",
                        Y: "0x0000000000000000000000000000000000000000000000000000000000000000",
                    },
                    deposit: 1000,
                    contributors: [
                        {
                            addr: "0x66d801a70615979d82c304b7db374d11c232db66",
                            stakedAmount: 1000,
                        }
                    ]
                },
            ];

            await expect(serviceNodeRewards.connect(owner).seedPublicKeyList(seedData)).to.be.reverted;
        });

        it("Fails if there are no contributors", async function () {
            const seedData = [
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 1000,
                    contributors: []
                },
            ];

            await expect(serviceNodeRewards.connect(owner).seedPublicKeyList(seedData)).to.be.reverted;
        });

        it("Supports 10 contributors", async function () {
            seedData = [
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 1000,
                    contributors: []
                },
            ];

            const contributorCount    = 10;
            const ethAddr             = "0x66d801a70615979d82c304b7db374d11c232db66";
            const stakePerContributor = seedData[0].deposit / contributorCount;
            for (let index = 0; index < contributorCount; index++) {
                seedData[0].contributors.push({addr: ethAddr, stakedAmount: stakePerContributor});
            }

            await serviceNodeRewards.connect(owner).seedPublicKeyList(seedData);
            expect(await serviceNodeRewards.serviceNodesLength()).to.equal(1);
            verifySeedData(await serviceNodeRewards.serviceNodes(1), seedData[0]);
        });

        it("Fails if there are 11 contributors (pre-migration Oxen has a 10 contributor limit)", async function () {
            seedData = [
                {
                    pubkey: {
                        X: "0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed",
                        Y: "0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab",
                    },
                    deposit: 1100,
                    contributors: []
                },
            ];

            const contributorCount    = 11;
            const ethAddr             = "0x66d801a70615979d82c304b7db374d11c232db66";
            const stakePerContributor = seedData[0].deposit / contributorCount;
            for (let index = 0; index < contributorCount; index++) {
                seedData[0].contributors.push({addr: ethAddr, stakedAmount: stakePerContributor});
            }

            await expect(serviceNodeRewards.connect(owner).seedPublicKeyList(seedData)).to.be.reverted;
        });
    });
});

