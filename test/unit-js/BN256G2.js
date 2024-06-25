const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BN256G2 Tests", function () {

    // NOTE: Hardcoded msg/DST that must match with the DST specified in C++
    // unit-test, see: eth-sn-contracts/test/cpp/test/src/hash.cpp
    let DOMAIN_SEPARATION_TAG = "0xff54977c9d08fb9098f6beae0e4634cb9b2d4c2b9c86f0b3e2f2f0073b73f51c";
    let MESSAGE               = "asdf";
    let contract;

    beforeEach(async function () {
        const factory = await ethers.getContractFactory("BN256G2");
        contract      = await factory.deploy();
    });

    describe("RFC9380 hashToField", function () {
      it("Produces different values w/ different message and same DST", async function () {
        const message1 = ethers.toUtf8Bytes("message 1");
        const message2 = ethers.toUtf8Bytes("message 2");

        const result1 = await contract.hashToField(message1, DOMAIN_SEPARATION_TAG);
        const result2 = await contract.hashToField(message2, DOMAIN_SEPARATION_TAG);

        expect(result1[0]).to.not.equal(result2[0]);
        expect(result1[1]).to.not.equal(result2[1]);
      });

      it("Returns the correct 2 values", async function () {
        const hexMsg = ethers.hexlify(ethers.toUtf8Bytes(MESSAGE));
        const result = await contract.hashToField(hexMsg, DOMAIN_SEPARATION_TAG);

        // NOTE: Values calculated via JS unit-test and set in: eth-sn-contracts/test/cpp/test/src/hash.cpp
        expect(result).to.have.length(2);
        expect(result[0]).to.equal("11032720900463547873271743099548770716954083165825879766348225717865290248407");
        expect(result[1]).to.equal("15644586462817709158587850387782908059942803533371602959682274737078222802151");
      });
    });

    describe("RFC9380 expand_message_xmd", function () {
      it("Test expand via keccak256", async function () {
        const hexMsg = ethers.hexlify(ethers.toUtf8Bytes(MESSAGE));
        await expect(contract.expandMessageXMDKeccak256(hexMsg, DOMAIN_SEPARATION_TAG)).to.not.be.reverted;

        const hexStrings = await contract.expandMessageXMDKeccak256(hexMsg, DOMAIN_SEPARATION_TAG);
        expect(hexStrings).to.have.length(3);

        // NOTE: Values calculated via JS unit-test and set in: eth-sn-contracts/test/cpp/test/src/hash.cpp
        expect(hexStrings[0]).to.equal("0xe8f4d933efbcf56796fe680e8d947406e18862ab351bea98c5d9f8888080fe6f");
        expect(hexStrings[1]).to.equal("0x097596243f18b9fa9d600eb8346663987b0153a3781e4a7b54bbbd833c00166c");
        expect(hexStrings[2]).to.equal("0x24824cfba40d05f96f25933446d22f4e2c4323fa0f13904a264439aea47d28be");
      });
    });

});
