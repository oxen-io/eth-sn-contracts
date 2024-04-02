const { expect } = require("chai");
const { ethers } = require("hardhat");

const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT = 50000000000000

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

    const ServiceNodeContributorFactory = await ethers.getContractFactory("ServiceNodeContributorFactory");
    const serviceNodeContributorFactory = await ServiceNodeContributorFactory.deploy(serviceNodeRewards);

    expect(await serviceNodeContributorFactory.stakingRewardsContract()).to.equal(await serviceNodeRewards.getAddress());
  });
});

describe("ServiceNodeContribution Contract Tests", function () {
    let MockERC20;
    let mockERC20;
    let ServiceNodeRewards;
    let serviceNodeRewards;
    let ServiceNodeContributorFactory;
    let serviceNodeContributorFactory;
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

        ServiceNodeContributorFactory = await ethers.getContractFactory("ServiceNodeContributorFactory");
        serviceNodeContributorFactory = await ServiceNodeContributorFactory.deploy(serviceNodeRewards);
    });


    it("Allows deployment of contributor contract and logs correctly", async function () {
        const [owner, operator] = await ethers.getSigners();
        await expect(serviceNodeContributorFactory.connect(operator).deployContributorContract(0,0,0,0))
            .to.emit(serviceNodeContributorFactory, 'NewServiceNodeContributionContract');
    });

    it("Does not allow contributions if operator hasn't contributed", async function () {
        const [owner, operator, contributor] = await ethers.getSigners();
        const tx = await serviceNodeContributorFactory.connect(operator).deployContributorContract(0,0,0,0);
        const receipt = await tx.wait();
        const event = receipt.logs[0];
        expect(event.eventName).to.equal("NewServiceNodeContributionContract");
        const serviceNodeContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
        const serviceNodeContribution = await ethers.getContractAt("ServiceNodeContribution", serviceNodeContributionAddress);

        const minContribution = await serviceNodeContribution.minimumContribution();
        await mockERC20.transfer(contributor, TEST_AMNT);
        await mockERC20.connect(contributor).approve(serviceNodeContributionAddress, minContribution);
        await expect(serviceNodeContribution.connect(contributor).contributeFunds(minContribution))
            .to.be.revertedWith("Operator has not contributed funds"); // checking for a revert due to the operator not having contributed
    });

    it("allows operator to contribute and records correct balance", async function () {
        const [owner, operator] = await ethers.getSigners();
        const tx = await serviceNodeContributorFactory.connect(operator).deployContributorContract(0,0,0,0);
        const receipt = await tx.wait();
        const event = receipt.logs[0];
        expect(event.eventName).to.equal("NewServiceNodeContributionContract");
        const serviceNodeContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
        const serviceNodeContribution = await ethers.getContractAt("ServiceNodeContribution", serviceNodeContributionAddress);

        const minContribution = await serviceNodeContribution.minimumContribution();
        await mockERC20.transfer(operator, TEST_AMNT);
        await mockERC20.connect(operator).approve(serviceNodeContributionAddress, minContribution);
        await expect(serviceNodeContribution.connect(operator).contributeOperatorFunds())
              .to.emit(serviceNodeContribution, "NewContribution")
              .withArgs(await operator.getAddress(), minContribution);

        await expect(await serviceNodeContribution.operatorContribution())
            .to.equal(minContribution);
        await expect(await serviceNodeContribution.totalContribution())
            .to.equal(minContribution);
        await expect(await serviceNodeContribution.numberContributors())
            .to.equal(1);
    });

    describe("After operator has set up funds", function () {
        beforeEach(async function () {
            const [owner, operator] = await ethers.getSigners();
            const tx = await serviceNodeContributorFactory.connect(operator).deployContributorContract(0,0,0,0);
            const receipt = await tx.wait();
            const event = receipt.logs[0];
            expect(event.eventName).to.equal("NewServiceNodeContributionContract");
            const serviceNodeContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
            serviceNodeContribution = await ethers.getContractAt("ServiceNodeContribution", serviceNodeContributionAddress);

            const minContribution = await serviceNodeContribution.minimumContribution();
            await mockERC20.transfer(operator, TEST_AMNT);
            await mockERC20.connect(operator).approve(serviceNodeContributionAddress, minContribution);
            await expect(serviceNodeContribution.connect(operator).contributeOperatorFunds())
                  .to.emit(serviceNodeContribution, "NewContribution")
                  .withArgs(await operator.getAddress(), minContribution);
        });

        it("Should be able to contribute funds as a contributor", async function () {
            const [owner, operator, contributor] = await ethers.getSigners();
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
            await expect(await serviceNodeContribution.numberContributors())
                .to.equal(2);
        });

        it("Should be able to have multiple contributors", async function () {
            const [owner, operator, contributor, contributor2] = await ethers.getSigners();
            const minContribution = await serviceNodeContribution.minimumContribution();
            let previousContribution = await serviceNodeContribution.totalContribution();
            await mockERC20.transfer(contributor, minContribution);
            await mockERC20.connect(contributor).approve(serviceNodeContribution, minContribution);
            await expect(serviceNodeContribution.connect(contributor).contributeFunds(minContribution))
                  .to.emit(serviceNodeContribution, "NewContribution")
                  .withArgs(await contributor.getAddress(), minContribution);
            const minContribution2 = await serviceNodeContribution.minimumContribution();
            await mockERC20.transfer(contributor2, minContribution2);
            await mockERC20.connect(contributor2).approve(serviceNodeContribution, minContribution2);
            await expect(serviceNodeContribution.connect(contributor2).contributeFunds(minContribution2))
                  .to.emit(serviceNodeContribution, "NewContribution")
                  .withArgs(await contributor2.getAddress(), minContribution2);
            await expect(await serviceNodeContribution.operatorContribution())
                .to.equal(previousContribution);
            await expect(await serviceNodeContribution.totalContribution())
                .to.equal(previousContribution + minContribution + minContribution2);
            await expect(await serviceNodeContribution.numberContributors())
                .to.equal(3);
        });

        it("Should not finalise if not full", async function () {
            const [owner, operator, contributor] = await ethers.getSigners();
            const minContribution = await serviceNodeContribution.minimumContribution();
            let previousContribution = await serviceNodeContribution.totalContribution();
            await mockERC20.transfer(contributor, minContribution);
            await mockERC20.connect(contributor).approve(serviceNodeContribution, minContribution);
            await expect(await serviceNodeContribution.connect(contributor).contributeFunds(minContribution))
                .to.emit(serviceNodeContribution, "NewContribution")
                .withArgs(await contributor.getAddress(), minContribution);
            await expect(serviceNodeContribution.connect(operator).finalizeNode(0,0,0,0,0))
                .to.be.revertedWith("Funding goal has not been met.");
        });

        it("Should not be able to overcapitalize", async function () {
            const [owner, operator, contributor, contributor2] = await ethers.getSigners();
            const stakingRequirement = await serviceNodeContribution.stakingRequirement();
            let previousContribution = await serviceNodeContribution.totalContribution();
            await mockERC20.transfer(contributor, stakingRequirement - previousContribution);
            await mockERC20.connect(contributor).approve(serviceNodeContribution, stakingRequirement - previousContribution + BigInt(1));
            await expect(serviceNodeContribution.connect(contributor).contributeFunds(stakingRequirement - previousContribution + BigInt(1)))
                .to.be.revertedWith("Contribution exceeds the funding goal.");
        });

        it("Should be able to finalise if funded", async function () {
            const [owner, operator, contributor, contributor2] = await ethers.getSigners();
            const stakingRequirement = await serviceNodeContribution.stakingRequirement();
            let previousContribution = await serviceNodeContribution.totalContribution();
            await mockERC20.transfer(contributor, stakingRequirement - previousContribution);
            await mockERC20.connect(contributor).approve(serviceNodeContribution, stakingRequirement - previousContribution);
            await expect(await serviceNodeContribution.connect(contributor).contributeFunds(stakingRequirement - previousContribution))
                  .to.emit(serviceNodeContribution, "NewContribution");
            await expect(await serviceNodeContribution.connect(operator).finalizeNode(0,0,0,0,0))
                .to.emit(serviceNodeContribution, "Finalized");
            expect(await mockERC20.balanceOf(serviceNodeRewards)).to.equal(stakingRequirement);
            expect(await serviceNodeRewards.totalNodes()).to.equal(1);
            expect(await serviceNodeContribution.finalized()).to.equal(true);
            expect(await mockERC20.balanceOf(serviceNodeContribution)).to.equal(0);
        });
    });
});

