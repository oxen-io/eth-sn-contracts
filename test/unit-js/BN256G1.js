// test/BN256G1Test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BN256G1 Library Tests", function () {
    let bn256G1Test;
    let FIELD_MODULUS;

    before(async function () {
        const BN256G1Test = await ethers.getContractFactory("BN256G1Test");
        bn256G1Test = await BN256G1Test.deploy();
        bn256G1Test.waitForDeployment();

        // Initialize FIELD_MODULUS
        FIELD_MODULUS = BigInt(
            "21888242871839275222246405745257275088696311157297823662689037894645226208583"
        );
    });

    it("should return the generator point P1", async function () {
        const P1 = await bn256G1Test.getGenerator();
        expect(P1.X).to.equal("1");
        expect(P1.Y).to.equal("2");
    });

    it("should correctly add two valid G1 points", async function () {
        const p1 = { X: "1", Y: "2" };
        const p2 = { X: "1", Y: "2" };

        const result = await bn256G1Test.addPoints(p1, p2);

        // Expected result calculated externally
        const expectedX = "1368015179489954701390400359078579693043519447331113978918064868415326638035";
        const expectedY = "9918110051302171585080402603319702774565515993150576347155970296011118125764";

        expect(result.X.toString()).to.equal(expectedX);
        expect(result.Y.toString()).to.equal(expectedY);
    });

    it("should correctly negate a G1 point", async function () {
        const p = { X: BigInt("1"), Y: BigInt("2") };
        const result = await bn256G1Test.negatePoint(p);

        const expectedY = FIELD_MODULUS - (p.Y % FIELD_MODULUS);

        expect(result.X.toString()).to.equal(p.X);
        expect(result.Y.toString()).to.equal(expectedY.toString());
    });

    it("should get the correct key for a G1 point", async function () {
        const p = { X: "1", Y: "2" };
        const result = await bn256G1Test.getKey(p);

        // Expected ABI-encoded result
        const abiCoder = new ethers.AbiCoder();
        const expected = abiCoder.encode(["uint256", "uint256"], [p.X, p.Y]);

        expect(result).to.equal(expected);
    });

    it("should fail to add when given an invalid curve point", async function () {
        const p1 = { X: "1", Y: "2" };
        const invalidPoint = { X: "1", Y: "1" }; // Not on the curve

        await expect(bn256G1Test.addPoints(p1, invalidPoint)).to.be.revertedWith(
            "Call to precompiled contract for add failed"
        );
    });

    it("should correctly add the generator to its negation to get zero point", async function () {
        const P1 = await bn256G1Test.getGenerator();
        const p = { X: P1[0], Y: P1[1] };
        const negP1 = await bn256G1Test.negatePoint(p);
        const negp = { X: negP1[0], Y: negP1[1] };

        const zeroPoint = await bn256G1Test.addPoints(p, negp);

        expect(zeroPoint.X.toString()).to.equal("0");
        expect(zeroPoint.Y.toString()).to.equal("0");
    });

    it("should correctly double the generator point", async function () {
        const P1 = await bn256G1Test.getGenerator();
        const p = { X: P1[0], Y: P1[1] };

        // Adding P1 to itself
        const result = await bn256G1Test.addPoints(p, p);

        // Expected result calculated externally
        const expectedX = "1368015179489954701390400359078579693043519447331113978918064868415326638035";
        const expectedY = "9918110051302171585080402603319702774565515993150576347155970296011118125764";

        expect(result.X.toString()).to.equal(expectedX);
        expect(result.Y.toString()).to.equal(expectedY);
    });
});

