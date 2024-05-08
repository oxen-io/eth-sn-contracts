const { expect } = require("chai");
const { ethers } = require("hardhat");

const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT = 50000000000000
const MAX_CONTRIBUTORS = 10;

describe("ServiceNodeContributionFactory Contract Tests", function () {
  it("Should deploy and set the staking rewards contract address correctly", async function () {
    // Deploy a mock ERC20 token
    try {
        // Deploy a mock ERC20 token
        MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20 = await MockERC20.deploy("SENT Token", "SENT", 9);
    } catch (error) {
        console.error("Error deploying MockERC20:", error);
    }

    [owner] = await ethers.getSigners();

    const ServiceNodeRewards = await ethers.getContractFactory("MockServiceNodeRewards");
    const serviceNodeRewards = await ServiceNodeRewards.deploy(mockERC20, STAKING_TEST_AMNT);

    const ServiceNodeContributionFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
    const serviceNodeContributionFactory = await ServiceNodeContributionFactory.deploy(serviceNodeRewards, MAX_CONTRIBUTORS);

    expect(await serviceNodeContributionFactory.stakingRewardsContract()).to.equal(await serviceNodeRewards.getAddress());
  });
});

describe("ServiceNodeContribution Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let ServiceNodeRewards;
    let serviceNodeRewards;
    let ServiceNodeContributionFactory;
    let serviceNodeContributionFactory;

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

        ServiceNodeContributionFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
        serviceNodeContributionFactory = await ServiceNodeContributionFactory.deploy(serviceNodeRewards, MAX_CONTRIBUTORS);
    });

    it("Allows deployment of contributor contract and logs correctly", async function () {
        const [owner, operator] = await ethers.getSigners();
        await expect(serviceNodeContributionFactory.connect(operator).deployContributionContract([0,0],[0,0,0,0]))
            .to.emit(serviceNodeContributionFactory, 'NewServiceNodeContributionContract');
    });

    describe("Deploy a contribution contract", function () {
        let serviceNodeContribution;
        let serviceNodeOperator;

        beforeEach(async function () {
            [serviceNodeOperator] = await ethers.getSigners();

            // NOTE: Deploy the contract
            const tx = await serviceNodeContributionFactory.connect(serviceNodeOperator).deployContributionContract([0,0],[0,0,0,0]);
            // NOTE: Get deployed contract address
            const receipt                        = await tx.wait();
            const event                          = receipt.logs[0];
            expect(event.eventName).to.equal("NewServiceNodeContributionContract");
            serviceNodeContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
            serviceNodeContribution        = await ethers.getContractAt("ServiceNodeContribution", serviceNodeContributionAddress);
        });


        it("Does not allow contributions if operator hasn't contributed", async function () {
            const [owner, contributor] = await ethers.getSigners();
            const minContribution      = await serviceNodeContribution.minimumContribution();
            await mockERC20.transfer(contributor, TEST_AMNT);
            await mockERC20.connect(contributor).approve(serviceNodeContributionAddress, minContribution);
            await expect(serviceNodeContribution.connect(contributor).contributeFunds(minContribution))
                .to.be.revertedWith("Operator has not contributed funds"); // checking for a revert due to the operator not having contributed
        });

        it("Cancel contribution contract before operator contributes", async function () {
            await expect(await serviceNodeContribution.connect(serviceNodeOperator)
                                                      .cancelNode()).to
                                                                    .emit(serviceNodeContribution, "Cancelled");

            expect(await serviceNodeContribution.contributorAddressesLength()).to.equal(0);
            expect(await serviceNodeContribution.totalContribution()).to.equal(0);
            expect(await serviceNodeContribution.operatorContribution()).to.equal(0);
        });

        it("Random wallet can not cancel contract (test onlyOperator() modifier)", async function () {
            const [owner] = await ethers.getSigners();

            randomWallet = ethers.Wallet.createRandom();
            randomWallet = randomWallet.connect(ethers.provider);
            owner.sendTransaction({to: randomWallet.address, value: BigInt(1 * 10 ** 18)});

            await expect(serviceNodeContribution.connect(randomWallet)
                                                .cancelNode()).to
                                                              .be
                                                              .reverted;
        });


        it("Prevents operator contributing less than min amount", async function () {
            const minContribution = await serviceNodeContribution.minimumContribution();
            await mockERC20.transfer(serviceNodeOperator, TEST_AMNT);
            await mockERC20.connect(serviceNodeOperator).approve(serviceNodeContributionAddress, minContribution);
            await expect(serviceNodeContribution.connect(serviceNodeOperator).contributeOperatorFunds(minContribution - BigInt(1), [0,0,0,0]))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("Allows operator to contribute and records correct balance", async function () {
            const minContribution = await serviceNodeContribution.minimumContribution();
            await mockERC20.transfer(serviceNodeOperator, TEST_AMNT);
            await mockERC20.connect(serviceNodeOperator).approve(serviceNodeContributionAddress, minContribution);
            await expect(serviceNodeContribution.connect(serviceNodeOperator).contributeOperatorFunds(minContribution, [0,0,0,0]))
                  .to.emit(serviceNodeContribution, "NewContribution")
                  .withArgs(await serviceNodeOperator.getAddress(), minContribution);

            await expect(await serviceNodeContribution.operatorContribution())
                .to.equal(minContribution);
            await expect(await serviceNodeContribution.totalContribution())
                .to.equal(minContribution);
            await expect(await serviceNodeContribution.contributorAddressesLength())
                .to.equal(1);
        });

        describe("After operator has set up funds", function () {
            beforeEach(async function () {
                const [owner] = await ethers.getSigners();
                const minContribution = await serviceNodeContribution.minimumContribution();
                await mockERC20.transfer(serviceNodeOperator, TEST_AMNT);
                await mockERC20.connect(serviceNodeOperator).approve(serviceNodeContributionAddress, minContribution);
                await expect(serviceNodeContribution.connect(serviceNodeOperator).contributeOperatorFunds(minContribution, [0,0,0,0]))
                      .to.emit(serviceNodeContribution, "NewContribution")
                      .withArgs(await serviceNodeOperator.getAddress(), minContribution);
            });

            it("Should be able to contribute funds as a contributor", async function () {
                const [owner, contributor] = await ethers.getSigners();
                const minContribution = await serviceNodeContribution.minimumContribution();
                let previousContribution = await serviceNodeContribution.totalContribution();
                await mockERC20.transfer(contributor, TEST_AMNT);
                await mockERC20.connect(contributor).approve(serviceNodeContribution, minContribution);
                await expect(serviceNodeContribution.connect(contributor).contributeFunds(minContribution))
                      .to.emit(serviceNodeContribution, "NewContribution")
                      .withArgs(await contributor.getAddress(), minContribution);
                await expect(await serviceNodeContribution.operatorContribution())
                    .to.equal(previousContribution);
                await expect(await serviceNodeContribution.totalContribution())
                    .to.equal(previousContribution + minContribution);
                await expect(await serviceNodeContribution.contributorAddressesLength())
                    .to.equal(2);
            });

            describe("Should be able to have multiple contributors w/min contribution", async function () {
                beforeEach(async function () {
                    // NOTE: Get operator contribution
                    const [owner, contributor1, contributor2] = await ethers.getSigners();
                    const previousContribution                = await serviceNodeContribution.totalContribution();

                    // NOTE: Contributor 1 w/ minContribution()
                    const minContribution1                   = await serviceNodeContribution.minimumContribution();
                    await mockERC20.transfer(contributor1, minContribution1);
                    await mockERC20.connect(contributor1).approve(serviceNodeContribution, minContribution1);
                    await expect(serviceNodeContribution.connect(contributor1)
                                                        .contributeFunds(minContribution1)).to
                                                                                           .emit(serviceNodeContribution, "NewContribution")
                                                                                           .withArgs(await contributor1.getAddress(), minContribution1);

                    // NOTE: Contributor 2 w/ minContribution()
                    const minContribution2 = await serviceNodeContribution.minimumContribution();
                    await mockERC20.transfer(contributor2, minContribution2);
                    await mockERC20.connect(contributor2)
                                   .approve(serviceNodeContribution,
                                           minContribution2);
                    await expect(serviceNodeContribution.connect(contributor2)
                                                        .contributeFunds(minContribution2)).to
                                                                                           .emit(serviceNodeContribution, "NewContribution")
                                                                                           .withArgs(await contributor2.getAddress(), minContribution2);

                    // NOTE: Check contribution values
                    expect(await serviceNodeContribution.operatorContribution()).to
                                                                                .equal(previousContribution);
                    expect(await serviceNodeContribution.totalContribution()).to
                                                                             .equal(previousContribution + minContribution1 + minContribution2);
                    expect(await serviceNodeContribution.contributorAddressesLength()).to
                                                                                      .equal(3);
                });

                it("Withdraw contributor 1", async function () {
                    const [owner, contributor1, contributor2] = await ethers.getSigners();

                    // NOTE: Collect contract initial state
                    const contributor1Amount         = await serviceNodeContribution.contributions(contributor1);
                    const totalContribution          = await serviceNodeContribution.totalContribution();
                    const contributorAddressesLength = await serviceNodeContribution.contributorAddressesLength();

                    // NOTE: Withdraw stake
                    await serviceNodeContribution.connect(contributor1).withdrawStake();

                    // NOTE: Test stake is withdrawn to contributor
                    expect(await mockERC20.balanceOf(contributor1)).to.equal(contributor1Amount);

                    // NOTE: Test repeated withdraw is reverted
                    await expect(serviceNodeContribution.connect(contributor1).withdrawStake()).to.be.reverted;

                    // NOTE: Test contract state
                    expect(await serviceNodeContribution.totalContribution()).to.equal(totalContribution - contributor1Amount);
                    expect(await serviceNodeContribution.contributorAddressesLength()).to.equal(contributorAddressesLength - BigInt(1));

                    // NOTE: Query the contributor addresses in the contract
                    const contributorArrayLengthAfter = await serviceNodeContribution.contributorAddressesLength();
                    const contributorArrayExpected    = [BigInt(await owner.getAddress()), BigInt(await contributor2.getAddress())];

                    let contributorArray              = [];
                    for (let index = 0; index < contributorArrayLengthAfter; index++) {
                        const address = await serviceNodeContribution.contributorAddresses(index);
                        contributorArray.push(address);
                    }

                    // NOTE: Compare the contributor array against what we expect
                    expect(contributorArrayExpected.length).to.equal(contributorArray.length);
                    for (let index = 0; index < contributorArrayExpected.length; index++)
                        expect(contributorArray[index]).to.equal(contributorArrayExpected[index]);
                });
            });

            it("Should not finalise if not full", async function () {
                const [owner, contributor] = await ethers.getSigners();
                const minContribution = await serviceNodeContribution.minimumContribution();
                let previousContribution = await serviceNodeContribution.totalContribution();
                await mockERC20.transfer(contributor, minContribution);
                await mockERC20.connect(contributor).approve(serviceNodeContribution, minContribution);
                await expect(await serviceNodeContribution.connect(contributor).contributeFunds(minContribution))
                    .to.emit(serviceNodeContribution, "NewContribution")
                    .withArgs(await contributor.getAddress(), minContribution);
                await expect(await serviceNodeContribution.connect(serviceNodeOperator).finalized())
                    .to.equal(false);
                await expect(await mockERC20.balanceOf(serviceNodeContribution))
                    .to.equal(previousContribution + minContribution);
            });

            it("Should not be able to overcapitalize", async function () {
                const [owner, contributor, contributor2] = await ethers.getSigners();
                const stakingRequirement = await serviceNodeContribution.stakingRequirement();
                let previousContribution = await serviceNodeContribution.totalContribution();
                await mockERC20.transfer(contributor, stakingRequirement - previousContribution);
                await mockERC20.connect(contributor).approve(serviceNodeContribution, stakingRequirement - previousContribution + BigInt(1));
                await expect(serviceNodeContribution.connect(contributor).contributeFunds(stakingRequirement - previousContribution + BigInt(1)))
                    .to.be.revertedWith("Contribution exceeds the funding goal.");
            });

            it("Should be finalise if funded", async function () {
                const [owner, contributor, contributor2] = await ethers.getSigners();
                const stakingRequirement = await serviceNodeContribution.stakingRequirement();
                let previousContribution = await serviceNodeContribution.totalContribution();
                await mockERC20.transfer(contributor, stakingRequirement - previousContribution);
                await mockERC20.connect(contributor).approve(serviceNodeContribution, stakingRequirement - previousContribution);
                await expect(await serviceNodeContribution.connect(contributor).contributeFunds(stakingRequirement - previousContribution))
                      .to.emit(serviceNodeContribution, "Finalized");
                expect(await mockERC20.balanceOf(serviceNodeRewards)).to.equal(stakingRequirement);
                expect(await serviceNodeRewards.totalNodes()).to.equal(1);
                expect(await serviceNodeContribution.finalized()).to.equal(true);
                expect(await mockERC20.balanceOf(serviceNodeContribution)).to.equal(0);

            });
        });
    });
});

describe("ServiceNodeContribution minimum contribution tests", function () {
    let MockERC20;
    let mockERC20;
    let ServiceNodeRewards;
    let serviceNodeRewards;
    let ServiceNodeContributionFactory;
    let serviceNodeContributionFactory;
    let serviceNodeContribution;

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

        ServiceNodeContributionFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
        serviceNodeContributionFactory = await ServiceNodeContributionFactory.deploy(serviceNodeRewards, MAX_CONTRIBUTORS);
        const [owner, operator, contributor] = await ethers.getSigners();
        const tx = await serviceNodeContributionFactory.connect(operator).deployContributionContract([0,0],[0,0,0,0]);
        const receipt = await tx.wait();
        const event = receipt.logs[0];
        expect(event.eventName).to.equal("NewServiceNodeContributionContract");
        const serviceNodeContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
        serviceNodeContribution = await ethers.getContractAt("ServiceNodeContribution", serviceNodeContributionAddress);
    });


    it('should return the correct minimum contribution when there is one last contributor', async function () {
        const contributionRemaining = 100;
        const numberContributors = 9;
        const maxContributors = 10;

        const minimumContribution = await serviceNodeContribution._minimumContribution(
            contributionRemaining,
            numberContributors,
            maxContributors
        );

        expect(minimumContribution).to.equal(100);
    });

    it('should return the correct minimum contribution when there are no contributors', async function () {
        const contributionRemaining = 15000;
        const numberContributors = 0;
        const maxContributors = 4;

        const minimumContribution = await serviceNodeContribution._minimumContribution(
            contributionRemaining,
            numberContributors,
            maxContributors
        );

        expect(minimumContribution).to.equal(3750);
    });

    it('should equally split minimum contribution', async function () {
        let contributionRemaining = BigInt(15000)
        let numberContributors = 0;
        const maxContributors = 4;
        for (let numberContributors = 0; numberContributors < maxContributors; numberContributors++) {
            const minimumContribution = await serviceNodeContribution._minimumContribution( contributionRemaining, numberContributors, maxContributors);
            contributionRemaining -= minimumContribution;
            expect(minimumContribution).to.equal(3750);
        }
        expect(contributionRemaining).to.equal(0)
    });

    it('should return the correct minimum contribution after a single contributor', async function () {
        const contributionRemaining = 15000 - 3750;
        const numberContributors = 1;
        const maxContributors = 10;

        const minimumContribution = await serviceNodeContribution._minimumContribution(
            contributionRemaining,
            numberContributors,
            maxContributors
        );

        expect(minimumContribution).to.equal(1250);
    });
});
