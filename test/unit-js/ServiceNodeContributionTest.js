const { expect } = require("chai");
const { ethers } = require("hardhat");

// NOTE: Constants
const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT         = 50000000000000

// Withdraw a contributor from the service node contribution contract
// `snContribution`. This function expects to succeed (e.g. the contributor must
// have successfully contributed to the contract prior).
async function withdrawContributor(sentToken, snContribution, contributor) {
    // NOTE: Collect contract initial state
    const contributorTokenBalanceBefore = await sentToken.balanceOf(contributor);
    const contributorAmount             = await snContribution.contributions(contributor);
    const totalContribution             = await snContribution.totalContribution();
    const contributorAddressesLength    = await snContribution.contributorAddressesLength();

    let contributorArrayBefore = [];
    for (let index = 0; index < contributorAddressesLength; index++) {
        const address = await snContribution.contributorAddresses(index);
        contributorArrayBefore.push(address);
    }

    // NOTE: Withdraw contribution
    await snContribution.connect(contributor).withdrawContribution();

    // NOTE: Test stake is withdrawn to contributor
    expect(await sentToken.balanceOf(contributor)).to.equal(contributorTokenBalanceBefore + contributorAmount);

    // NOTE: Test repeated withdraw is reverted
    await expect(snContribution.connect(contributor).withdrawContribution()).to.be.reverted;

    // NOTE: Test contract state
    expect(await snContribution.totalContribution()).to.equal(totalContribution - contributorAmount);
    expect(await snContribution.contributorAddressesLength()).to.equal(contributorAddressesLength - BigInt(1));

    // NOTE: Calculate the expected contributor array, emulate the swap-n-pop
    // idiom as used in Solidity.
    let contributorArrayExpected = contributorArrayBefore;
    for (let index = 0; index < contributorArrayExpected.length; index++) {
        if (BigInt(contributorArrayExpected[index]) === BigInt(await contributor.getAddress())) {
            contributorArrayExpected[index] = contributorArrayExpected[contributorArrayExpected.length - 1];
            contributorArrayExpected.pop();
            break;
        }
    }

    // NOTE: Query the contributor addresses in the contract
    const contributorArrayLengthAfter = await snContribution.contributorAddressesLength();
    let contributorArray = [];
    for (let index = 0; index < contributorArrayLengthAfter; index++) {
        const address = await snContribution.contributorAddresses(index);
        contributorArray.push(address);
    }

    // NOTE: Compare the contributor array against what we expect
    expect(contributorArrayExpected).to.deep.equal(contributorArray);
}

describe("ServiceNodeContribution Contract Tests", function () {
    // NOTE: Contract factories for deploying onto the blockchain
    let sentTokenContractFactory;
    let snRewardsContractFactory;
    let snContributionContractFactory;

    // NOTE: Contract instances
    let sentToken;             // ERC20 token contract
    let snRewards;             // Rewards contract that pays out SN's
    let snContributionFactory; // Smart contract that deploys `ServiceNodeContribution` contracts

    // NOTE: Load the contracts factories in
    before(async function () {
        sentTokenContractFactory      = await ethers.getContractFactory("MockERC20");
        snRewardsContractFactory      = await ethers.getContractFactory("MockServiceNodeRewards");
        snContributionContractFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
    });

    // NOTE: Initialise the contracts for each test
    beforeEach(async function () {
        // NOTE: Deploy contract instances
        sentToken             = await sentTokenContractFactory.deploy("SENT Token", "SENT", 9);
        snRewards             = await snRewardsContractFactory.deploy(sentToken, STAKING_TEST_AMNT);
        snContributionFactory = await snContributionContractFactory.deploy(snRewards);
    });

    it("Verify staking rewards contract is set", async function () {
        expect(await snContributionFactory.stakingRewardsContract()).to
                                                                    .equal(await snRewards.getAddress());
    });

    it("Allows deployment of multi-sn contribution contract and emits log correctly", async function () {
        const [owner, operator] = await ethers.getSigners();
        await expect(snContributionFactory.connect(operator)
                                          .deployContributionContract([1,2],[3,4,5,6])).to
                                                                                       .emit(snContributionFactory, 'NewServiceNodeContributionContract');
    });

    describe("Deploy a contribution contract", function () {
        let snContribution;        // Multi-sn contribution contract created by `snContributionFactory`
        let snOperator;            // The owner of the multi-sn contribution contract, `snContribution`
        let snContributionAddress; // The address of the `snContribution` contract

        beforeEach(async function () {
            [snOperator] = await ethers.getSigners();

            // NOTE: Deploy the contract
            const tx = await snContributionFactory.connect(snOperator)
                                                  .deployContributionContract([1,2],[3,4,5,6]);

            // NOTE: Get TX logs to determine contract address
            const receipt                  = await tx.wait();
            const event                    = receipt.logs[0];
            expect(event.eventName).to.equal("NewServiceNodeContributionContract");

            // NOTE: Get deployed contract address
            snContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
            snContribution        = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);
        });

        describe("Minimum contribution tests", function () {
            it('Correct minimum contribution when there is one last contributor', async function () {
                const contributionRemaining = 100;
                const numberContributors = 9;
                const maxContributors = 10;

                const minimumContribution = await snContribution.calcMinimumContribution(
                    contributionRemaining,
                    numberContributors,
                    maxContributors
                );

                expect(minimumContribution).to.equal(100);
            });

            it('Correct minimum contribution when there are no contributors', async function () {
                const contributionRemaining = 15000;
                const numberContributors = 0;
                const maxContributors = 4;

                const minimumContribution = await snContribution.calcMinimumContribution(
                    contributionRemaining,
                    numberContributors,
                    maxContributors
                );

                expect(minimumContribution).to.equal(3750);
            });

            it('Equally split minimum contribution across 4 contributors', async function () {
                let contributionRemaining = BigInt(15000)
                let numberContributors    = 0;
                const maxContributors     = 4;
                for (let numberContributors = 0; numberContributors < maxContributors; numberContributors++) {
                    const minimumContribution  = await snContribution.calcMinimumContribution(contributionRemaining, numberContributors, maxContributors);
                    contributionRemaining     -= minimumContribution;
                    expect(minimumContribution).to.equal(3750);
                }
                expect(contributionRemaining).to.equal(0)
            });

            it('Correct minimum contribution after a single contributor', async function () {
                const contributionRemaining = 15000 - 3750;
                const numberContributors    = 1;
                const maxContributors       = 10;

                const minimumContribution = await snContribution.calcMinimumContribution(
                    contributionRemaining,
                    numberContributors,
                    maxContributors
                );

                expect(minimumContribution).to.equal(1250);
            });

            it('Calc min contribution API returns correct operator minimum contribution', async function () {
                const maxContributors             = await snContribution.maxContributors();
                const stakingRequirement          = await snContribution.stakingRequirement();
                const minimumOperatorContribution = await snContribution.minimumOperatorContribution(stakingRequirement);
                for (let i = 1; i < maxContributors; i++) {
                    const amount = await snContribution.calcMinimumContribution(
                        stakingRequirement,
                        /*numContributors*/ 0,
                        i
                    );
                    expect(amount).to.equal(minimumOperatorContribution);
                }
            });

            it('Minimum contribution reverts with bad parameters numbers', async function () {
                const stakingRequirement = await snContribution.stakingRequirement();

                // NOTE: Test no contributors
                await expect(snContribution.calcMinimumContribution(stakingRequirement, /*numberContributors*/ 0, /*maxContributors*/ 0)).to
                                                                                                                                         .be
                                                                                                                                         .reverted

                // NOTE: Test number of contributers greater than max contributors
                await expect(snContribution.calcMinimumContribution(stakingRequirement, /*numberContributors*/ 3, /*maxContributors*/ 2)).to
                                                                                                                                         .be
                                                                                                                                         .reverted

                // NOTE: Test 0 staking requirement
                await expect(snContribution.calcMinimumContribution(0, /*numberContributors*/ 1, /*maxContributors*/ 2)).to
                                                                                                                        .be
                                                                                                                        .reverted

                // NOTE: Test number of contributors equal to max contributors (e.g. division by 0)
                await expect(snContribution.calcMinimumContribution(stakingRequirement, /*numberContributors*/ 3, /*maxContributors*/ 3)).to
                                                                                                                                         .be
                                                                                                                                         .reverted
            });
        });

        it("Does not allow contributions if operator hasn't contributed", async function () {
            const [owner, contributor] = await ethers.getSigners();
            const minContribution      = await snContribution.minimumContribution();
            await sentToken.transfer(contributor, TEST_AMNT);
            await sentToken.connect(contributor).approve(snContributionAddress, minContribution);
            await expect(snContribution.connect(contributor).contributeFunds(minContribution))
                .to.be.revertedWith("Operator has not contributed funds"); // checking for a revert due to the operator not having contributed
        });

        it("Cancel contribution contract before operator contributes", async function () {
            await expect(await snContribution.connect(snOperator)
                                                      .cancelNode()).to
                                                                    .emit(snContribution, "Cancelled");

            expect(await snContribution.contributorAddressesLength()).to.equal(0);
            expect(await snContribution.totalContribution()).to.equal(0);
            expect(await snContribution.operatorContribution()).to.equal(0);
        });

        it("Random wallet can not cancel contract (test onlyOperator() modifier)", async function () {
            const [owner] = await ethers.getSigners();

            randomWallet = ethers.Wallet.createRandom();
            randomWallet = randomWallet.connect(ethers.provider);
            owner.sendTransaction({to: randomWallet.address, value: BigInt(1 * 10 ** 18)});

            await expect(snContribution.connect(randomWallet)
                                                .cancelNode()).to
                                                              .be
                                                              .reverted;
        });

        it("Operator is not allowed to call `contributeFunds` before `contributeOperatorFunds`", async function () {
            const minContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
            await expect(snContribution.connect(snOperator).contributeFunds(minContribution)).to.be.reverted;
        });

        it("Prevents operator contributing less than min amount", async function () {
            const minContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
            await expect(snContribution.connect(snOperator).contributeOperatorFunds(minContribution - BigInt(1), [3,4,5,6], []))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("Allows operator to contribute and records correct balance", async function () {
            const minContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
            await expect(snContribution.connect(snOperator).contributeOperatorFunds(minContribution, [3,4,5,6], []))
                  .to.emit(snContribution, "NewContribution")
                  .withArgs(await snOperator.getAddress(), minContribution);

            await expect(await snContribution.operatorContribution())
                .to.equal(minContribution);
            await expect(await snContribution.totalContribution())
                .to.equal(minContribution);
            await expect(await snContribution.contributorAddressesLength())
                .to.equal(1);
        });

        describe("After operator has set up funds", function () {
            beforeEach(async function () {
                const [owner]         = await ethers.getSigners();
                const minContribution = await snContribution.minimumContribution();

                await sentToken.transfer(snOperator, TEST_AMNT);
                await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
                await expect(snContribution.connect(snOperator)
                                           .contributeOperatorFunds(minContribution, [3,4,5,6], [])).to
                                                                                                .emit(snContribution, "NewContribution")
                                                                                                .withArgs(await snOperator.getAddress(), minContribution);
            });

            it("Should be able to contribute funds as a contributor", async function () {
                const [owner, contributor] = await ethers.getSigners();
                const minContribution = await snContribution.minimumContribution();
                let previousContribution = await snContribution.totalContribution();
                await sentToken.transfer(contributor, TEST_AMNT);
                await sentToken.connect(contributor).approve(snContribution, minContribution);
                await expect(snContribution.connect(contributor).contributeFunds(minContribution))
                      .to.emit(snContribution, "NewContribution")
                      .withArgs(await contributor.getAddress(), minContribution);
                await expect(await snContribution.operatorContribution())
                    .to.equal(previousContribution);
                await expect(await snContribution.totalContribution())
                    .to.equal(previousContribution + minContribution);
                await expect(await snContribution.contributorAddressesLength())
                    .to.equal(2);
            });

            it("Should allow operator top-ups", async function() {
                const minContribution = await snContribution.minimumContribution();
                const topup = BigInt(9_000000000);
                await expect(topup).to.be.below(minContribution)
                const currTotal = await snContribution.totalContribution();
                await sentToken.connect(snOperator).approve(snContribution, topup);
                await expect(snContribution.connect(snOperator).contributeFunds(topup))
                      .to.emit(snContribution, "NewContribution")
                      .withArgs(await snOperator.getAddress(), topup);
                await expect(await snContribution.operatorContribution())
                    .to.equal(currTotal + topup);
                await expect(await snContribution.totalContribution())
                    .to.equal(currTotal + topup);
                await expect(await snContribution.contributorAddressesLength())
                    .to.equal(1);
                await expect(await snContribution.minimumContribution()).to.equal(
                    minContribution - BigInt(1_000000000));

                await expect(await snContribution.getContributions()).to.deep.equal(
                        [[snOperator.address], [BigInt(STAKING_TEST_AMNT / 4 + 9_000000000)]])
            });

            describe("Should be able to have multiple contributors w/min contribution", async function () {
                beforeEach(async function () {
                    // NOTE: Get operator contribution
                    const [owner, contributor1, contributor2] = await ethers.getSigners();
                    const previousContribution                = await snContribution.totalContribution();

                    // NOTE: Contributor 1 w/ minContribution()
                    const minContribution1                   = await snContribution.minimumContribution();
                    await sentToken.transfer(contributor1, minContribution1);
                    await sentToken.connect(contributor1).approve(snContribution, minContribution1);
                    await expect(snContribution.connect(contributor1)
                                                        .contributeFunds(minContribution1)).to
                                                                                           .emit(snContribution, "NewContribution")
                                                                                           .withArgs(await contributor1.getAddress(), minContribution1);

                    // NOTE: Contributor 2 w/ minContribution()
                    const minContribution2 = await snContribution.minimumContribution();
                    await sentToken.transfer(contributor2, minContribution2);
                    await sentToken.connect(contributor2)
                                   .approve(snContribution,
                                           minContribution2);
                    await expect(snContribution.connect(contributor2)
                                                        .contributeFunds(minContribution2)).to
                                                                                           .emit(snContribution, "NewContribution")
                                                                                           .withArgs(await contributor2.getAddress(), minContribution2);

                    // NOTE: Check contribution values
                    expect(await snContribution.operatorContribution()).to
                                                                       .equal(previousContribution);
                    expect(await snContribution.totalContribution()).to
                                                                    .equal(previousContribution + minContribution1 + minContribution2);
                    expect(await snContribution.contributorAddressesLength()).to
                                                                             .equal(3);
                });

                it("Should allow contributor top-ups", async function() {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();
                    const minContribution = await snContribution.minimumContribution();
                    const initialOperatorContrib = await snContribution.operatorContribution();
                    const initialContribution = await snContribution.totalContribution();

                    const topup1 = BigInt(1_000000000);
                    await sentToken.transfer(contributor1, topup1);
                    await expect(topup1).to.be.below(minContribution)
                    await sentToken.connect(contributor1).approve(snContribution, topup1);
                    await expect(snContribution.connect(contributor1).contributeFunds(topup1))
                          .to.emit(snContribution, "NewContribution")
                          .withArgs(await contributor1.getAddress(), topup1);

                    const minContribution2 = await snContribution.minimumContribution();
                    const topup2 = BigInt(13_000000000);
                    await sentToken.transfer(contributor2, topup2);
                    await expect(topup2).to.be.below(minContribution2)
                    await sentToken.connect(contributor2).approve(snContribution, topup2);
                    await expect(snContribution.connect(contributor2).contributeFunds(topup2))
                          .to.emit(snContribution, "NewContribution")
                          .withArgs(await contributor2.getAddress(), topup2);

                    await expect(await snContribution.operatorContribution())
                        .to.equal(initialOperatorContrib);
                    await expect(await snContribution.totalContribution())
                        .to.equal(initialContribution + topup1 + topup2);
                    await expect(await snContribution.contributorAddressesLength())
                        .to.equal(3);
                    await expect(await snContribution.minimumContribution()).to.equal(
                        minContribution - BigInt(2_000000000));

                    await expect(await snContribution.getContributions()).to.deep.equal(
                        [
                            [owner.address, contributor1.address, contributor2.address],
                            [BigInt(STAKING_TEST_AMNT / 4), BigInt(STAKING_TEST_AMNT / 12 + 1_000000000), BigInt(STAKING_TEST_AMNT / 12 + 13_000000000)]
                        ])
                });

                describe("Withdraw contributor 1", async function () {
                    beforeEach(async function () {
                        const [owner, contributor1, contributor2] = await ethers.getSigners();

                        // NOTE: Advance time
                        await network.provider.send("evm_increaseTime", [60 * 60 * 24]);
                        await network.provider.send("evm_mine");

                        await withdrawContributor(sentToken, snContribution, contributor1);
                    });

                    describe("Withdraw contributor 2", async function () {
                        beforeEach(async function () {
                            const [owner, contributor1, contributor2] = await ethers.getSigners();
                            await withdrawContributor(sentToken, snContribution, contributor2);
                        });

                        describe("Contributor 1, 2 rejoin", async function() {
                            beforeEach(async function() {
                                // NOTE: Get operator contribution
                                const [owner, contributor1, contributor2] = await ethers.getSigners();
                                const previousContribution                = await snContribution.totalContribution();

                                const stakingRequirement = await snContribution.stakingRequirement();
                                expect(previousContribution).to.equal(await snContribution.minimumOperatorContribution(stakingRequirement));

                                // NOTE: Contributor 1 w/ minContribution()
                                const minContribution1                   = await snContribution.minimumContribution();
                                await sentToken.transfer(contributor1, minContribution1);
                                await sentToken.connect(contributor1).approve(snContribution, minContribution1);
                                await expect(snContribution.connect(contributor1)
                                                                    .contributeFunds(minContribution1)).to
                                                                                                       .emit(snContribution, "NewContribution")
                                                                                                       .withArgs(await contributor1.getAddress(), minContribution1);

                                // NOTE: Contributor 2 w/ minContribution()
                                const minContribution2 = await snContribution.minimumContribution();
                                await sentToken.transfer(contributor2, minContribution2);
                                await sentToken.connect(contributor2)
                                               .approve(snContribution,
                                                       minContribution2);
                                await expect(snContribution.connect(contributor2)
                                                                    .contributeFunds(minContribution2)).to
                                                                                                       .emit(snContribution, "NewContribution")
                                                                                                       .withArgs(await contributor2.getAddress(), minContribution2);

                                // NOTE: Check contribution values
                                expect(await snContribution.operatorContribution()).to
                                                                                   .equal(previousContribution);
                                expect(await snContribution.totalContribution()).to
                                                                                .equal(previousContribution + minContribution1 + minContribution2);
                                expect(await snContribution.contributorAddressesLength()).to
                                                                                         .equal(3);
                            });

                            it("Cancel node and check contributor funds have been returned", async function() {
                                const [owner, contributor1, contributor2] = await ethers.getSigners();
                                
                                // Get initial balances
                                const initialBalance1 = await sentToken.balanceOf(contributor1.address);
                                const initialBalance2 = await sentToken.balanceOf(contributor2.address);
                                
                                // Get contribution amounts
                                const contribution1 = await snContribution.contributions(contributor1.address);
                                const contribution2 = await snContribution.contributions(contributor2.address);

                                // Cancel the node
                                await expect(snContribution.connect(owner).cancelNode())
                                    .to.emit(snContribution, "Cancelled");
                                
                                // Check final balances
                                const finalBalance1 = await sentToken.balanceOf(contributor1.address);
                                const finalBalance2 = await sentToken.balanceOf(contributor2.address);
                                
                                expect(finalBalance1).to.equal(initialBalance1 + contribution1);
                                expect(finalBalance2).to.equal(initialBalance2 + contribution2);
                            });
                        });
                    });
                });
            });

            it("Max contributors cannot be exceeded", async function () {
                expect(await snContribution.contributorAddressesLength()).to.equal(1); // SN operator
                expect(await snContribution.maxContributors()).to.equal(await snRewards.maxContributors());

                const signers         = [];
                const maxContributors = Number(await snContribution.maxContributors()) - 1; // Remove SN operator from list

                for (let i = 0; i < maxContributors + 1 /*Add one more to exceed*/; i++) {
                    // NOTE: Create wallet
                    let wallet = await ethers.Wallet.createRandom();
                    wallet     = wallet.connect(ethers.provider);

                    // NOTE: Fund the wallet
                    await sentToken.transfer(await wallet.getAddress(), TEST_AMNT);
                    await snOperator.sendTransaction({
                        to:    await wallet.getAddress(),
                        value: ethers.parseEther("1.0")
                    });

                    signers.push(wallet);
                }

                // NOTE: Contribute
                const minContribution = await snContribution.minimumContribution();
                for (let i = 0; i < signers.length; i++) {
                    const signer          = signers[i];
                    await sentToken.connect(signer).approve(snContribution, minContribution);

                    if (i == (signers.length - 1)) {
                        await expect(snContribution.connect(signer)
                                                   .contributeFunds(minContribution)).to
                                                                                     .be
                                                                                     .reverted;
                    } else {
                        await expect(snContribution.connect(signer)
                                                   .contributeFunds(minContribution)).to
                                                                                     .emit(snContribution, "NewContribution")
                                                                                     .withArgs(await signer.getAddress(), minContribution);
                    }
                }

                expect(await snContribution.totalContribution()).to.equal(await snContribution.stakingRequirement());
                expect(await snContribution.contributorAddressesLength()).to.equal(await snContribution.maxContributors());
                expect(await snContribution.finalized()).to.equal(true);
            });

            it("Should not finalise if not full", async function () {
                const [owner, contributor] = await ethers.getSigners();
                const minContribution = await snContribution.minimumContribution();
                let previousContribution = await snContribution.totalContribution();
                await sentToken.transfer(contributor, minContribution);
                await sentToken.connect(contributor).approve(snContribution, minContribution);
                await expect(await snContribution.connect(contributor).contributeFunds(minContribution))
                    .to.emit(snContribution, "NewContribution")
                    .withArgs(await contributor.getAddress(), minContribution);
                await expect(await snContribution.connect(snOperator).finalized())
                    .to.equal(false);
                await expect(await sentToken.balanceOf(snContribution))
                    .to.equal(previousContribution + minContribution);
            });

            it("Should not be able to overcapitalize", async function () {
                const [owner, contributor, contributor2] = await ethers.getSigners();
                const stakingRequirement = await snContribution.stakingRequirement();
                let previousContribution = await snContribution.totalContribution();
                await sentToken.transfer(contributor, stakingRequirement - previousContribution);
                await sentToken.connect(contributor).approve(snContribution, stakingRequirement - previousContribution + BigInt(1));
                await expect(snContribution.connect(contributor).contributeFunds(stakingRequirement - previousContribution + BigInt(1)))
                    .to.be.revertedWith("Contribution exceeds the funding goal.");
            });

            describe("Finalise w/ 1 contributor", async function () {
                beforeEach(async function () {
                    const [owner, contributor1] = await ethers.getSigners();
                    const stakingRequirement = await snContribution.stakingRequirement();
                    let previousContribution = await snContribution.totalContribution();

                    await sentToken.transfer(contributor1, stakingRequirement - previousContribution);
                    await sentToken.connect(contributor1)
                                   .approve(snContribution, stakingRequirement - previousContribution);

                    await expect(await snContribution.connect(contributor1)
                                                     .contributeFunds(stakingRequirement - previousContribution)).to
                                                                                                                 .emit(snContribution, "Finalized");

                    expect(await sentToken.balanceOf(snRewards)).to.equal(stakingRequirement);
                    expect(await snRewards.totalNodes()).to.equal(1);
                    expect(await snContribution.finalized()).to.equal(true);
                    expect(await snContribution.cancelled()).to.equal(false);
                    expect(await sentToken.balanceOf(snContribution)).to.equal(0);
                });

                it("Check withdraw is rejected via operator and contributor", async function () {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();
                    await expect(snContribution.connect(owner).withdrawContribution()).to
                                                                                      .be
                                                                                      .reverted;
                    await expect(snContribution.connect(contributor1).withdrawContribution()).to
                                                                                             .be
                                                                                             .reverted;

                    // NOTE: Contributor 2 never contributed, but we test withdraw anyway
                    await expect(snContribution.connect(contributor2).withdrawContribution()).to
                                                                                             .be
                                                                                             .reverted;

                });

                it("Check cancel is rejected after finalisation", async function () {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();
                    await expect(snContribution.connect(owner).cancelNode()).to
                                                                            .be
                                                                            .reverted;
                    await expect(snContribution.connect(contributor1).cancelNode()).to
                                                                                   .be
                                                                                   .reverted;

                    // NOTE: Contributor 2 never contributed, but we test cancel anyway
                    await expect(snContribution.connect(contributor2).cancelNode()).to
                                                                                   .be
                                                                                   .reverted;

                });

                it("Check reset contract is reverted with invalid parameters", async function () {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();
                    const zero                                = BigInt(0);
                    const one                                 = BigInt(1);

                    // NOTE: Test reset w/ contributor1 and contributor2 (of
                    // which contributor2 is not a one of the actual
                    // contributors of the contract).
                    await expect(snContribution.connect(contributor1).resetContract(zero,[])).to
                                                                                          .be
                                                                                          .reverted;
                    await expect(snContribution.connect(contributor2).resetContract(zero,[])).to
                                                                                          .be
                                                                                          .reverted;

                    // NOTE: Operator resets, first with an amount insufficient
                    // to reinitialise the contract
                    await expect(snContribution.connect(contributor2).resetContract(zero,[])).to
                                                                                          .be
                                                                                          .reverted;

                    // NOTE: Then try with an amount too large
                    const stakingRequirement = await snContribution.stakingRequirement();
                    await expect(snContribution.connect(contributor2).resetContract(stakingRequirement + one,[])).to
                                                                                                              .be
                                                                                                              .reverted;

                    // NOTE: Then try an amount that is too 1 token too less
                    const minOperatorContribution = await snContribution.minimumOperatorContribution(stakingRequirement);
                    await expect(snContribution.connect(contributor2).resetContract(minOperatorContribution - one,[])).to
                                                                                                                   .be
                                                                                                                   .reverted;
                });

                it("Check reset contract works with min contribution", async function () {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();
                    const stakingRequirement                  = await snContribution.stakingRequirement();
                    const minOperatorContribution             = await snContribution.minimumOperatorContribution(stakingRequirement);

                    // NOTE: Test reset w/ contributor1 and contributor2 (of
                    // which contributor2 is not a one of the actual
                    // contributors of the contract).
                    await expect(snContribution.connect(contributor1).resetContract(minOperatorContribution,[])).to
                                                                                                             .be
                                                                                                             .reverted;
                    await expect(snContribution.connect(contributor2).resetContract(minOperatorContribution,[])).to
                                                                                                             .be
                                                                                                             .reverted;

                    // NOTE: Test reset w/ operator
                    const blsSignatureBefore      = await snContribution.blsSignature();
                    const blsPubkeyBefore         = await snContribution.blsPubkey();
                    const serviceNodeParamsBefore = await snContribution.serviceNodeParams();
                    const maxContributorsBefore   = await snContribution.maxContributors();

                    await sentToken.connect(owner).approve(snContributionAddress, minOperatorContribution);
                    await expect(snContribution.connect(owner).resetContract(minOperatorContribution,[])).to
                                                                                                      .emit(snContribution, "NewContribution");

                    // NOTE: Verify contract state
                    expect(await snContribution.contributorAddressesLength()).to.equal(1);
                    expect(await snContribution.contributions(owner)).to.equal(minOperatorContribution);
                    expect(await snContribution.contributorAddresses(0)).to.equal(await owner.getAddress());
                    expect(await snContribution.finalized()).to.equal(false);
                    expect(await snContribution.cancelled()).to.equal(false);
                    expect(await snContribution.blsSignature()).to.deep.equal(blsSignatureBefore);
                    expect(await snContribution.blsPubkey()).to.deep.equal(blsPubkeyBefore);
                    expect(await snContribution.serviceNodeParams()).to.deep.equal(serviceNodeParamsBefore);
                    expect(await snContribution.maxContributors()).to.equal(maxContributorsBefore);
                });

                it("Check we can rescue ERC20 tokens sent after finalisation", async function() {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();

                    // NOTE: Check that the contract SENT balance is empty
                    const contractBalance = await sentToken.balanceOf(snContribution);
                    expect(contractBalance).to.equal(BigInt(0));

                    // NOTE: Transfer tokens to the contract after it was finalised
                    await sentToken.transfer(snContribution, TEST_AMNT);

                    // NOTE: Check contributors can't rescue the token
                    await expect(snContribution.connect(contributor1)
                                               .rescueERC20(sentToken)).to.be.reverted;
                    await expect(snContribution.connect(contributor2)
                                               .rescueERC20(sentToken)).to.be.reverted;

                    // NOTE: Check that the operator can rescue the tokens
                    const balanceBefore = await sentToken.balanceOf(owner);
                    expect(await snContribution.connect(owner)
                                               .rescueERC20(sentToken));

                    // NOTE: Verify the balances
                    const balanceAfter         = await sentToken.balanceOf(owner);
                    const contractBalanceAfter = await sentToken.balanceOf(snContribution);
                    expect(balanceBefore + BigInt(TEST_AMNT)).to.equal(balanceAfter);
                    expect(contractBalanceAfter).to.equal(BigInt(0));

                    // NOTE: Tokes are rescued, contract is empty, test that no
                    // one can rescue, not even the operator (because the
                    // balance of the contract is empty).
                    await expect(snContribution.connect(contributor1)
                                               .rescueERC20(sentToken)).to.be.reverted;
                    await expect(snContribution.connect(contributor2)
                                               .rescueERC20(sentToken)).to.be.reverted;
                    await expect(snContribution.connect(owner)
                                               .rescueERC20(sentToken)).to.be.reverted;
                });
            });

            it("Should revert withdrawal if less than 24 hours have passed", async function () {
                const [owner, contributor] = await ethers.getSigners();
                const minContribution = await snContribution.minimumContribution();
                // Setting up contribution
                await sentToken.transfer(contributor, TEST_AMNT);
                await sentToken.connect(contributor).approve(snContribution, minContribution);
                await snContribution.connect(contributor).contributeFunds(minContribution);

                // Attempting to withdraw before 24 hours
                await network.provider.send("evm_increaseTime", [60 * 60 * 23]); // Fast forward time by 23 hours
                await network.provider.send("evm_mine");

                // This withdrawal should fail
                await expect(snContribution.connect(contributor).withdrawContribution())
                    .to.be.revertedWith("Withdrawal unavailable: 24 hours have not passed");
            });

            it("Should allow withdrawal and return funds after 24 hours have passed", async function () {
                const [owner, contributor] = await ethers.getSigners();
                const minContribution = await snContribution.minimumContribution();
                // Setting up contribution
                await sentToken.transfer(contributor, TEST_AMNT);
                await sentToken.connect(contributor).approve(snContribution, minContribution);
                await snContribution.connect(contributor).contributeFunds(minContribution);

                // Waiting for 24 hours
                await network.provider.send("evm_increaseTime", [60 * 60 * 24]); // Fast forward time by 24 hours
                await network.provider.send("evm_mine");

                // Checking the initial balance before withdrawal
                const initialBalance = await sentToken.balanceOf(contributor.getAddress());

                // Performing the withdrawal
                await expect(snContribution.connect(contributor).withdrawContribution())
                    .to.emit(snContribution, "WithdrawContribution")
                    .withArgs(await contributor.getAddress(), minContribution);

                // Verify that the funds have returned to the contributor
                const finalBalance = await sentToken.balanceOf(contributor.getAddress());
                expect(finalBalance).to.equal(initialBalance + minContribution);
            });
        });
    });

    describe("Reserved Contributions testing minimum amounts", function () {
        let snOperator;
        let snContributionAddress;
        let reservedContributor1;
        let reservedContributor2;
        let reservedContributor3;
        let ownerContribution;

        beforeEach(async function () {
            [snOperator, reservedContributor1, reservedContributor2, reservedContributor3] = await ethers.getSigners();
            
            let tx = await snContributionFactory.connect(snOperator)
                .deployContributionContract([1,2], [3,4,5,6]);

            const receipt = await tx.wait();
            const event = receipt.logs[0];
            snContributionAddress = event.args[0];
            snContribution = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);

            ownerContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, ownerContribution);
        });

        it("should succeed with valid reserved contributions: [25% operator, 10%, 10%, 15%, 40%]", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor3.address, stakedAmount: STAKING_TEST_AMNT * 15 / 100 },
                { addr: ethers.Wallet.createRandom().address, stakedAmount: STAKING_TEST_AMNT * 40 / 100 }
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors)).to.not.be.reverted;
        });

        it("should fail with duplicate reserved contributions", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 15 / 100 },
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors)).to.be.revertedWith("duplicate address in reserved contributors");
        });

        it("should fail with invalid reserved contributions: [25% operator, 10%, 5%]", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 5 / 100 }
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("should succeed with valid reserved contributions: [25% operator, 70%, 5%]", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 70 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 5 / 100 }
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors)).to.not.be.reverted;
        });

        it("should fail with invalid reserved contributions order: [25%, 5%, 70%]", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 5 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 70 / 100 }
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("should fail if operator contribution is less than 25%", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 76 / 100 }
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution - BigInt(1), [3,4,5,6], reservedContributors))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("should succeed with exactly 25% operator stake", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 75 / 100 }
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors)).to.not.be.reverted;
        });

        it("should fail if total contributions exceed 100%", async function () {
            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 50 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 30 / 100 }
            ];

            await expect(snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors))
                .to.be.revertedWith("Contribution exceeds the funding goal.");
        });
    });

    describe("Reserved Contributions", function () {
        let snContribution;
        let snOperator;
        let snContributionAddress;
        let reservedContributor1;
        let reservedContributor2;
        let contribution1 = STAKING_TEST_AMNT / 3;
        let contribution2 = STAKING_TEST_AMNT / 4;
        let ownerContribution;

        beforeEach(async function () {
            [snOperator, reservedContributor1, reservedContributor2] = await ethers.getSigners();

            const reservedContributors = [
                { addr: reservedContributor1.address, stakedAmount: contribution1 },
                { addr: reservedContributor2.address, stakedAmount: contribution2 }
            ];

            const tx = await snContributionFactory.connect(snOperator)
                .deployContributionContract([1,2], [3,4,5,6]);

            const receipt = await tx.wait();
            const event = receipt.logs[0];
            snContributionAddress = event.args[0];
            snContribution = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);

            ownerContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, ownerContribution);
            await snContribution.connect(snOperator).contributeOperatorFunds(ownerContribution, [3,4,5,6], reservedContributors);
        });

        it("Should correctly set reserved contributions", async function () {
            const reservedContribution1 = await snContribution.reservedContributions(reservedContributor1.address);
            const reservedContribution2 = await snContribution.reservedContributions(reservedContributor2.address);

            expect(reservedContribution1).to.equal(contribution1);
            expect(reservedContribution2).to.equal(contribution2);
        });

        it("Should correctly calculate total reserved contribution", async function () {
            const totalReserved = await snContribution.totalReservedContribution();
            expect(totalReserved).to.equal(contribution1 + contribution2);
        });

        it("Should allow reserved contributor to contribute reserved funds", async function () {
            await sentToken.transfer(reservedContributor1.address, contribution1);
            await sentToken.connect(reservedContributor1).approve(snContribution.getAddress(), contribution1);

            await expect(snContribution.connect(reservedContributor1).contributeFunds(contribution1))
                .to.emit(snContribution, "NewContribution")
                .withArgs(reservedContributor1.address, contribution1);

            const contribution = await snContribution.contributions(reservedContributor1.address);
            expect(contribution).to.equal(contribution1);

            const remainingReserved = await snContribution.reservedContributions(reservedContributor1.address);
            expect(remainingReserved).to.equal(0);
        });

        it("Should prevent reserved contributor to contribute less than their reserved funds", async function () {
            await sentToken.transfer(reservedContributor1.address, contribution1);
            await sentToken.connect(reservedContributor1).approve(snContribution.getAddress(), contribution1);

            await expect(snContribution.connect(reservedContributor1).contributeFunds(contribution1 - 1))
                .to.be.revertedWith("Insufficient contribution for reserved contributor");

            const contribution = await snContribution.contributions(reservedContributor1.address);
            expect(contribution).to.equal(0);

            const remainingReserved = await snContribution.reservedContributions(reservedContributor1.address);
            expect(remainingReserved).to.equal(contribution1);
        });

        it("Should allow reserved contributor to contribute more than their reserved funds", async function () {
            await sentToken.transfer(reservedContributor1.address, contribution1 + 1);
            await sentToken.connect(reservedContributor1).approve(snContribution.getAddress(), contribution1 + 1);

            await expect(snContribution.connect(reservedContributor1).contributeFunds(contribution1 + 1))
                .to.emit(snContribution, "NewContribution")
                .withArgs(reservedContributor1.address, contribution1 + 1);

            const contribution = await snContribution.contributions(reservedContributor1.address);
            expect(contribution).to.equal(contribution1 + 1);

            const remainingReserved = await snContribution.reservedContributions(reservedContributor1.address);
            expect(remainingReserved).to.equal(0);
        });

        it("Should update minimum contribution based on reserved amounts", async function () {
            const minContribution = await snContribution.minimumContribution();
            const expectedMin = await snContribution.calcMinimumContribution(
                await snContribution.stakingRequirement() -ownerContribution - BigInt(contribution1 + contribution2),
                3,
                await snContribution.maxContributors()
            );
            expect(minContribution).to.equal(expectedMin);
        });

        it("Should not allow other contributors to fill the node before reserved contributors have participated", async function () {
            const amountToFillNode = await snContribution.stakingRequirement() - ownerContribution;
            const [contributor] = await ethers.getSigners();

            await sentToken.transfer(contributor.address, amountToFillNode);
            await sentToken.connect(contributor).approve(snContribution.getAddress(), amountToFillNode);

            await expect(snContribution.connect(contributor).contributeFunds(amountToFillNode))
                .to.be.revertedWith("Contribution exceeds the funding goal.");
        });
    });

    describe("updateServiceNodeParams and updateBLSPubkey functions", function () {
        let snContribution;
        let snOperator;
        let newParams;

        beforeEach(async function () {
            [snOperator] = await ethers.getSigners();

            // Deploy the contract
            const tx = await snContributionFactory.connect(snOperator)
                .deployContributionContract([1,2],[3,4,5,6]);

            const receipt = await tx.wait();
            const event = receipt.logs[0];
            const snContributionAddress = event.args[0];
            snContribution = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);

            // Set up new params for testing
            newParams = {
                serviceNodePubkey: 8,
                serviceNodeSignature1: 9,
                serviceNodeSignature2: 10,
                fee: 11,
            };

            // Set up new pubkey for testing
            newPubkey = {
                X: 8,
                Y: 9,
            };

            // Contribute operator funds
            const minContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
            await snContribution.connect(snOperator).contributeOperatorFunds(minContribution, [3,4,5,6], []);
        });

        it("Should allow operator to update params before other contributions", async function () {
            await expect(snContribution.connect(snOperator).updateServiceNodeParams(newParams))
                .to.not.be.reverted;

            const updatedParams = await snContribution.serviceNodeParams();
            expect(updatedParams.serviceNodePubkey).to.equal(newParams.serviceNodePubkey);
            expect(updatedParams.operatorFee).to.equal(newParams.operatorFee);
            expect(updatedParams.operatorSignature).to.deep.equal(newParams.operatorSignature);
        });

        it("Should allow operator to update pubkey before other contributions", async function () {
            await expect(snContribution.connect(snOperator).updateBLSPubkey(newPubkey))
                .to.not.be.reverted;

            const updatedPubkey = await snContribution.blsPubkey();
            expect(updatedPubkey.X).to.equal(newPubkey.X);
            expect(updatedPubkey.Y).to.equal(newPubkey.Y);
        });

        it("Should fail to update params after another contributor has joined", async function () {
            const [, contributor] = await ethers.getSigners();
            const minContribution = await snContribution.minimumContribution();

            // Add another contributor
            await sentToken.transfer(contributor, TEST_AMNT);
            await sentToken.connect(contributor).approve(snContribution.target, minContribution);
            await snContribution.connect(contributor).contributeFunds(minContribution);

            await expect(snContribution.connect(snOperator).updateServiceNodeParams(newParams))
                .to.be.revertedWith("Cannot update params: Other contributors have already joined.");
        });

        it("Should fail to update pubkey after another contributor has joined", async function () {
            const [, contributor] = await ethers.getSigners();
            const minContribution = await snContribution.minimumContribution();

            // Add another contributor
            await sentToken.transfer(contributor, TEST_AMNT);
            await sentToken.connect(contributor).approve(snContribution.target, minContribution);
            await snContribution.connect(contributor).contributeFunds(minContribution);

            await expect(snContribution.connect(snOperator).updateBLSPubkey(newPubkey))
                .to.be.revertedWith("Cannot update pubkey: Other contributors have already joined.");
        });

        it("Should fail to update params after contract is finalized", async function () {
            // Finalize the contract
            const stakingRequirement = await snContribution.stakingRequirement();
            const currentContribution = await snContribution.totalContribution();
            const remainingContribution = stakingRequirement - currentContribution;

            await sentToken.transfer(snOperator, remainingContribution);
            await sentToken.connect(snOperator).approve(snContribution.target, remainingContribution);
            await snContribution.connect(snOperator).contributeFunds(remainingContribution);

            // Try to update params after finalization
            await expect(snContribution.connect(snOperator).updateServiceNodeParams(newParams))
                .to.be.revertedWith("Cannot update params: Node has already been finalized.");
        });

        it("Should fail to update pubkey after contract is finalized", async function () {
            // Finalize the contract
            const stakingRequirement = await snContribution.stakingRequirement();
            const currentContribution = await snContribution.totalContribution();
            const remainingContribution = stakingRequirement - currentContribution;

            await sentToken.transfer(snOperator, remainingContribution);
            await sentToken.connect(snOperator).approve(snContribution.target, remainingContribution);
            await snContribution.connect(snOperator).contributeFunds(remainingContribution);

            // Try to update pubkey after finalization
            await expect(snContribution.connect(snOperator).updateBLSPubkey(newPubkey))
                .to.be.revertedWith("Cannot update pubkey: Node has already been finalized.");
        });

        it("Should update params after contract reset", async function () {
            // Finalize the contract
            const stakingRequirement = await snContribution.stakingRequirement();
            const currentContribution = await snContribution.totalContribution();
            const remainingContribution = stakingRequirement - currentContribution;

            await sentToken.transfer(snOperator, remainingContribution);
            await sentToken.connect(snOperator).approve(snContribution.target, remainingContribution);
            await snContribution.connect(snOperator).contributeFunds(remainingContribution);

            // Reset the contract
            const minOperatorContribution = await snContribution.minimumOperatorContribution(stakingRequirement);
            await sentToken.connect(snOperator).approve(snContribution.target, minOperatorContribution);
            await snContribution.connect(snOperator).resetContract(minOperatorContribution,[]);

            // Update params after reset
            await expect(snContribution.connect(snOperator).updateServiceNodeParams(newParams))
                .to.not.be.reverted;

            const updatedParams = await snContribution.serviceNodeParams();
            expect(updatedParams.serviceNodePubkey).to.equal(newParams.serviceNodePubkey);
            expect(updatedParams.operatorFee).to.equal(newParams.operatorFee);
            expect(updatedParams.operatorSignature).to.deep.equal(newParams.operatorSignature);
        });

        it("Should update pubkey after contract reset", async function () {
            // Finalize the contract
            const stakingRequirement = await snContribution.stakingRequirement();
            const currentContribution = await snContribution.totalContribution();
            const remainingContribution = stakingRequirement - currentContribution;

            await sentToken.transfer(snOperator, remainingContribution);
            await sentToken.connect(snOperator).approve(snContribution.target, remainingContribution);
            await snContribution.connect(snOperator).contributeFunds(remainingContribution);

            // Reset the contract
            const minOperatorContribution = await snContribution.minimumOperatorContribution(stakingRequirement);
            await sentToken.connect(snOperator).approve(snContribution.target, minOperatorContribution);
            await snContribution.connect(snOperator).resetContract(minOperatorContribution,[]);

            // Update pubkey after reset
            await expect(snContribution.connect(snOperator).updateBLSPubkey(newPubkey))
                .to.not.be.reverted;

            const updatedPubkey = await snContribution.blsPubkey();
            expect(updatedPubkey.X).to.equal(newPubkey.X);
            expect(updatedPubkey.Y).to.equal(newPubkey.Y);
        });
    });
});
