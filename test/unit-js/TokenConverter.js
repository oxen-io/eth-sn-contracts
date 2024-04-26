const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT = 50000000000000

/**
 * Calculates the numerator and denominator for a given rate and token decimals.
 *
 * @param {number} rate - The floating-point conversion rate.
 * @param {number} decimalsA - The number of decimals for token A.
 * @param {number} decimalsB - The number of decimals for token B.
 * @return {Object} An object containing the numerator and denominator.
 */
function calculateFraction(rate, decimalsA, decimalsB) {
  // Determine the scaling factor based on the token decimals
  const scaleFactor = 10000;
  
  // Scale the rate according to the highest decimal place
  const scaledRate = rate * scaleFactor;
  
  // Find the greatest common divisor for scaledRate and scaleFactor
  const gcd = (a, b) => b ? gcd(b, a % b) : a;
  const divisor = gcd(scaleFactor, scaledRate % scaleFactor);
  
  // Simplify the numerator and denominator
  const numerator = BigInt(scaledRate / divisor) * BigInt(10) ** BigInt(decimalsB);
  const denominator = BigInt(scaleFactor / divisor) * BigInt(10) ** BigInt(decimalsA);
  
  return {
    numerator: numerator,
    denominator: denominator
  };
}


describe("TokenConverter Contract Tests", function () {
    const rate = 0.75;
    const rate2 = 2;
    const decimalsTokenA = 18; // WOxen has 18 decimals
    const decimalsTokenB = 9; // Sent to have 9 decimals
    const firstRate = calculateFraction(rate, decimalsTokenA, decimalsTokenB);
    const secondRate = calculateFraction(rate2, decimalsTokenA, decimalsTokenB);
    let TokenAERC20;
    let tokenAERC20;
    let TokenBERC20;
    let tokenBERC20;
    let TokenConverter;
    let tokenConverter;
    let owner;
    let user;
    let testAmount = 1000;
    let bigAtomicTestAmount = ethers.parseUnits(testAmount.toString(), decimalsTokenA);
    let testAmountInContract = testAmount * 10;
    let bigAtomicTestAmountInContract = ethers.parseUnits("10000", decimalsTokenB);

    beforeEach(async function () {
        // Deploy a mock ERC20 token
        try {
            TokenAERC20 = await ethers.getContractFactory("MockERC20");
            tokenAERC20 = await TokenAERC20.deploy("WOxen Token", "WOXEN", decimalsTokenA);
        } catch (error) {
            console.error("Error deploying TokenAERC20:", error);
        }
        try {
            TokenBERC20 = await ethers.getContractFactory("MockERC20");
            tokenBERC20 = await TokenBERC20.deploy("SENT Token", "SENT", decimalsTokenB);
        } catch (error) {
            console.error("Error deploying TokenAERC20:", error);
        }

        [owner, user] = await ethers.getSigners();

        TokenConverter = await ethers.getContractFactory("TokenConverter");
        tokenConverter = await TokenConverter.deploy(tokenAERC20, tokenBERC20, firstRate.numerator, firstRate.denominator);

        await tokenAERC20.transfer(user, bigAtomicTestAmount * BigInt(2));
        await tokenAERC20.connect(user).approve(tokenConverter, bigAtomicTestAmount * BigInt(2));

    });

    it("Should deploy and set the correct owner", async function () {
        expect(await tokenConverter.owner()).to.equal(owner.address);
    });

    it("Should have correct converstion rate", async function () {
        expect(await tokenConverter.conversionRateNumerator()).to.equal(firstRate.numerator);
        expect(await tokenConverter.conversionRateDenominator()).to.equal(firstRate.denominator);
    });

    it("Should be able to deposit to it", async function () {
        await tokenBERC20.approve(tokenConverter, bigAtomicTestAmountInContract);
        await tokenConverter.depositTokenB(bigAtomicTestAmountInContract);
        expect(await tokenBERC20.balanceOf(tokenConverter)).to.equal(bigAtomicTestAmountInContract);
    });
    it("Should be able to change conversion rate", async function () {
        await tokenConverter.updateConversionRate(secondRate.numerator, secondRate.denominator);
        expect(await tokenConverter.conversionRateNumerator()).to.equal(secondRate.numerator);
        expect(await tokenConverter.conversionRateDenominator()).to.equal(secondRate.denominator);
    });
    
    describe("After seeding converter contract with funds", function () {
        beforeEach(async function () {
            let testAmountInContract = ethers.parseUnits("10000", decimalsTokenB);
            await tokenBERC20.approve(tokenConverter, bigAtomicTestAmountInContract);
            await tokenConverter.depositTokenB(bigAtomicTestAmountInContract)
        });

        it("Should be able to convert funds", async function () {
            await tokenConverter.connect(user).convertTokens(bigAtomicTestAmount);
            expect(await tokenBERC20.balanceOf(user)).to.equal(ethers.parseUnits((testAmount * rate).toString(), decimalsTokenB));
        });

        it("Should be able to convert funds, change rate and convert again", async function () {
            await tokenConverter.connect(user).convertTokens(bigAtomicTestAmount);
            expect(await tokenBERC20.balanceOf(user)).to.equal(ethers.parseUnits((testAmount * rate).toString(), decimalsTokenB));
            await tokenConverter.updateConversionRate(secondRate.numerator, secondRate.denominator);
            await tokenConverter.connect(user).convertTokens(bigAtomicTestAmount);
            expect(await tokenBERC20.balanceOf(user)).to.equal(ethers.parseUnits((testAmount * (rate + rate2)).toString(), decimalsTokenB));
        });
    });
});
