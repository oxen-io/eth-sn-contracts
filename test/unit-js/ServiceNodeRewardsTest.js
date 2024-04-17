const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

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
            // Example values for BN256G1 X and Y coordinates (These are arbitrary 32-byte hexadecimal values)
            let P = [
                BigInt("0x0b5e634d0407c021e9e9dd9d03c4965810e236fef0955ab345e1d049a0438ec6"),
                BigInt("0x1dbb7bf2b1f5340d4b5c466a0641b00cd3a9d9588c7bcad1c3158bdcc65c3332"),
            ];

            // Convert BigInt to hex strings
            const pkX = [P[0]];
            const pkY = [P[1]];
            const amounts = [1000]; // Example token amounts

            await serviceNodeRewards.connect(owner).seedPublicKeyList(pkX, pkY, amounts);

            expect(await serviceNodeRewards.serviceNodesLength()).to.equal(1);
            let aggregate_pubkey = await serviceNodeRewards.aggregatePubkey();
            expect(aggregate_pubkey[0] == P[0])
            expect(aggregate_pubkey[1] == P[1])
        });

        it("Should correctly seed public key list with multiple items", async function () {
            // Example values for BN256G1 X and Y coordinates (These are arbitrary 32-byte hexadecimal values)
            let P = [
                BigInt("0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed"),
                BigInt("0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab"),
                BigInt("0x2ef6b73ab4486484de80681753a6a90c6a88a71f60aace9520fe6bb8bb8de34e"),
                BigInt("0x29b8f2a87a758a89c394b121298b946dce9ada3226b5d008e54e54ddcd9e5227"),
            ];

            const pkX = [P[0], P[2]];
            const pkY = [P[1], P[3]];
            const amounts = [1000, 2000]; // Example token amounts

            await serviceNodeRewards.connect(owner).seedPublicKeyList(pkX, pkY, amounts);
            let expected_aggregate_pubkey = [
                BigInt("0x040a638a13320ea807115f1e7865c89c70d2d3df83e2e8c3eaea519e18b6e6b0"),
                BigInt("0x019081a4475388be53e1088f6ec0dd79f99fc794709b9cf8b1ad401a9c4d3413"),
            ];
            let aggregate_pubkey = await serviceNodeRewards.aggregatePubkey();
            expect(aggregate_pubkey[0] == expected_aggregate_pubkey[0])
            expect(aggregate_pubkey[1] == expected_aggregate_pubkey[1])

            expect(await serviceNodeRewards.serviceNodesLength()).to.equal(2);

        });

        it("Should fail to seed public key list with duplicate items", async function () {
            // Example values for BN256G1 X and Y coordinates (These are arbitrary 32-byte hexadecimal values)
            let P = [
                BigInt("0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed"),
                BigInt("0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab"),
                BigInt("0x12c59fb45c483177873406e5b74a2e6914fe25a591185f30d2788e737da6f2ed"),
                BigInt("0x016e56f330d11faaf90ec281b1c4184e98a52d4043075fcbe45a976de0f795ab"),
            ];

            const pkX = [P[0], P[2]];
            const pkY = [P[1], P[3]];
            const amounts = [1000, 2000]; // Example token amounts
            await expect(serviceNodeRewards.connect(owner).seedPublicKeyList(pkX, pkY, amounts))
                .to.be.revertedWithCustomError(serviceNodeRewards, "BLSPubkeyAlreadyExists")
        });
        
    });
});

