const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("TokenVestingStaking Contract Tests", function () {

    beforeEach(async function () {
        [owner, beneficiary] = await ethers.getSigners();

        HashToField = await ethers.getContractFactory("HashToField");
        hashToField = await HashToField.deploy();
    });

    describe("hash_to_field", function () {
      it("should return two uint256 values", async function () {
        const message = "asdf";
        const hexMsg = ethers.hexlify(ethers.toUtf8Bytes(message));

        const result = await hashToField.hash_to_field(hexMsg, hexMsg);

        expect(result).to.have.length(2);
        expect(result[0]).to.equal("18488821436036968639067232489934022592333274628566486098353443781605964295553");
        expect(result[1]).to.equal("7774746543242992034824500334882847626558424832512738634355427079977301983471");

      });

      it("should return different values for different inputs", async function () {
        const message1 = ethers.toUtf8Bytes("message 1");
        const message2 = ethers.toUtf8Bytes("message 2");
        const dst = ethers.toUtf8Bytes("test dst");

        const result1 = await hashToField.hash_to_field(message1, dst);
        const result2 = await hashToField.hash_to_field(message2, dst);

        expect(result1[0]).to.not.equal(result2[0]);
        expect(result1[1]).to.not.equal(result2[1]);
      });
    });

    describe("expand_message_xmd_keccak256", function () {
      it("should not revert", async function () {
        const message = "asdf";
        const hexMsg = ethers.hexlify(ethers.toUtf8Bytes(message));

        await expect(hashToField.expand_message_xmd_keccak256(hexMsg, hexMsg)).to.not.be.reverted;

        const hexStrings = await hashToField.expand_message_xmd_keccak256(hexMsg, hexMsg);
        expect(hexStrings).to.have.length(3);
        expect(hexStrings[0]).to.equal("0xb7dfc070382dc6f51e559031b14d8f0f2a573d61127c7cb791d4b4608a74ff01");
        expect(hexStrings[1]).to.equal("0x6d9ce93fab2366b5ce3c850bbd8835e879af2a342ad6bffbaf731fb93126a3f4");
        expect(hexStrings[2]).to.equal("0x8a82641e464475fe7637f75324eef9a103cbbf53ec1a3324c1e0baf6b05e92e5");
      });
    });

});
