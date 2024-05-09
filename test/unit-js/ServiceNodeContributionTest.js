const { expect } = require("chai");
const { ethers } = require("hardhat");

// NOTE: Constants
const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT         = 50000000000000
const MAX_CONTRIBUTORS  = 10;

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
        snContributionFactory = await snContributionContractFactory.deploy(snRewards, MAX_CONTRIBUTORS);
    });

    it("Verify staking rewards contract is set", async function () {
        expect(await snContributionFactory.stakingRewardsContract()).to
                                                                    .equal(await snRewards.getAddress());
    });

    it("Allows deployment of multi-sn contribution contract and emits log correctly", async function () {
        const [owner, operator] = await ethers.getSigners();
        await expect(snContributionFactory.connect(operator)
                                          .deployContributionContract([0,0],[0,0,0,0])).to
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
                                                  .deployContributionContract([0,0],[0,0,0,0]);

            // NOTE: Get TX logs to determine contract address
            const receipt                  = await tx.wait();
            const event                    = receipt.logs[0];
            expect(event.eventName).to.equal("NewServiceNodeContributionContract");

            // NOTE: Get deployed contract address
            snContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
            snContribution        = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);
        });

        describe("Minimum contribution tests", function () {
            it('should return the correct minimum contribution when there is one last contributor', async function () {
                const contributionRemaining = 100;
                const numberContributors = 9;
                const maxContributors = 10;

                const minimumContribution = await snContribution._minimumContribution(
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

                const minimumContribution = await snContribution._minimumContribution(
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
                    const minimumContribution  = await snContribution._minimumContribution( contributionRemaining, numberContributors, maxContributors);
                    contributionRemaining     -= minimumContribution;
                    expect(minimumContribution).to.equal(3750);
                }
                expect(contributionRemaining).to.equal(0)
            });

            it('Correct minimum contribution after a single contributor', async function () {
                const contributionRemaining = 15000 - 3750;
                const numberContributors    = 1;
                const maxContributors       = 10;

                const minimumContribution = await snContribution._minimumContribution(
                    contributionRemaining,
                    numberContributors,
                    maxContributors
                );

                expect(minimumContribution).to.equal(1250);
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


        it("Prevents operator contributing less than min amount", async function () {
            const minContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
            await expect(snContribution.connect(snOperator).contributeOperatorFunds(minContribution - BigInt(1), [0,0,0,0]))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("Allows operator to contribute and records correct balance", async function () {
            const minContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
            await expect(snContribution.connect(snOperator).contributeOperatorFunds(minContribution, [0,0,0,0]))
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
                                           .contributeOperatorFunds(minContribution, [0,0,0,0])).to
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

                it("Withdraw contributor 1", async function () {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();

                    // NOTE: Collect contract initial state
                    const contributor1Amount         = await snContribution.contributions(contributor1);
                    const totalContribution          = await snContribution.totalContribution();
                    const contributorAddressesLength = await snContribution.contributorAddressesLength();

                    // NOTE: Withdraw stake
                    await snContribution.connect(contributor1).withdrawStake();

                    // NOTE: Test stake is withdrawn to contributor
                    expect(await sentToken.balanceOf(contributor1)).to.equal(contributor1Amount);

                    // NOTE: Test repeated withdraw is reverted
                    await expect(snContribution.connect(contributor1).withdrawStake()).to.be.reverted;

                    // NOTE: Test contract state
                    expect(await snContribution.totalContribution()).to.equal(totalContribution - contributor1Amount);
                    expect(await snContribution.contributorAddressesLength()).to.equal(contributorAddressesLength - BigInt(1));

                    // NOTE: Query the contributor addresses in the contract
                    const contributorArrayLengthAfter = await snContribution.contributorAddressesLength();
                    const contributorArrayExpected    = [BigInt(await owner.getAddress()), BigInt(await contributor2.getAddress())];

                    let contributorArray              = [];
                    for (let index = 0; index < contributorArrayLengthAfter; index++) {
                        const address = await snContribution.contributorAddresses(index);
                        contributorArray.push(address);
                    }

                    // NOTE: Compare the contributor array against what we expect
                    expect(contributorArrayExpected.length).to.equal(contributorArray.length);
                    for (let index = 0; index < contributorArrayExpected.length; index++)
                        expect(contributorArray[index]).to.equal(contributorArrayExpected[index]);
                });
            });

            it("Max contributors cannot be exceeded", async function () {
                expect(await snContribution.contributorAddressesLength()).to.equal(1); // SN operator
                expect(await snContribution.maxContributors()).to.equal(MAX_CONTRIBUTORS);

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

            it("Should be finalise if funded", async function () {
                const [owner, contributor, contributor2] = await ethers.getSigners();
                const stakingRequirement = await snContribution.stakingRequirement();
                let previousContribution = await snContribution.totalContribution();
                await sentToken.transfer(contributor, stakingRequirement - previousContribution);
                await sentToken.connect(contributor).approve(snContribution, stakingRequirement - previousContribution);
                await expect(await snContribution.connect(contributor).contributeFunds(stakingRequirement - previousContribution))
                      .to.emit(snContribution, "Finalized");
                expect(await sentToken.balanceOf(snRewards)).to.equal(stakingRequirement);
                expect(await snRewards.totalNodes()).to.equal(1);
                expect(await snContribution.finalized()).to.equal(true);
                expect(await sentToken.balanceOf(snContribution)).to.equal(0);

            });
        });
    });
});
