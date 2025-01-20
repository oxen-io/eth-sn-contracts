const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SESH Contract", function () {
  let SESH, sesh;
  let owner, addr1, addr2, addr3;
  const initialSupply = ethers.parseUnits("1000000", 9); // 1,000,000 tokens with 9 decimals

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();

    SESH = await ethers.getContractFactory("SESH");
    sesh = await SESH.deploy(initialSupply, owner.address);
  });

  describe("Constructor", function () {
    it("Should set correct name, symbol, supplyCap, and initial totalSupply", async function () {
      expect(await sesh.name()).to.equal("Session");
      expect(await sesh.symbol()).to.equal("SESH");

      const supplyCap = await sesh.supplyCap();
      expect(supplyCap).to.equal(initialSupply);

      const totalSupply = await sesh.totalSupply();
      expect(totalSupply).to.equal(initialSupply);

      const ownerBalance = await sesh.balanceOf(owner.address);
      expect(ownerBalance).to.equal(initialSupply);
    });

    it("Should revert if totalSupply_ = 0", async function () {
      await expect(
        SESH.deploy(0, owner.address)
      ).to.be.revertedWith("Shared: uint input is empty");
    });

    it("Should revert if receiverGenesisAddress is zero", async function () {
      await expect(
        SESH.deploy(initialSupply, ethers.ZeroAddress)
      ).to.be.revertedWith("Shared: Zero-address is not permitted");
    });
  });

  describe("Decimals override", function () {
    it("Should return 9 as decimals", async function () {
      expect(await sesh.decimals()).to.equal(9);
    });
  });

  describe("Ownership (Ownable2Step)", function () {
    it("Owner should be the deployer initially", async function () {
      expect(await sesh.owner()).to.equal(owner.address);
    });

    it("Non-owner cannot transfer ownership", async function () {
      await expect(
        sesh.connect(addr1).transferOwnership(addr2.address)
      ).to.be.revertedWithCustomError(sesh, "OwnableUnauthorizedAccount");
    });

    it("Should transfer ownership using two-step process", async function () {
      const transferTx = await sesh.transferOwnership(addr1.address);
      await transferTx.wait();

      expect(await sesh.owner()).to.equal(owner.address);

      const acceptTx = await sesh.connect(addr1).acceptOwnership();
      await acceptTx.wait();

      expect(await sesh.owner()).to.equal(addr1.address);
    });
  });

  describe("setPool", function () {
    it("Only the owner can set the pool", async function () {
      await expect(sesh.connect(addr1).setPool(addr2.address)).to.be.revertedWithCustomError(sesh,
        "OwnableUnauthorizedAccount"
      );
      const tx = await sesh.setPool(addr2.address);
      await tx.wait();
      expect(await sesh.pool()).to.equal(addr2.address);
    });

    it("Should revert if setting the pool to the zero address", async function () {
      await expect(sesh.setPool(ethers.ZeroAddress)).to.be.revertedWith(
        "Shared: Zero-address is not permitted"
      );
    });
  });

  describe("Burning tokens", function () {
    it("Should allow a user to burn tokens they own", async function () {
      const transferAmount = ethers.parseUnits("1000", 9);
      await sesh.transfer(addr1.address, transferAmount);
      const burnAmount = ethers.parseUnits("500", 9);
      await sesh.connect(addr1).burn(burnAmount);
      const addr1Balance = await sesh.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(transferAmount - burnAmount);
      const totalSupplyAfterBurn = await sesh.totalSupply();
      expect(totalSupplyAfterBurn).to.equal(initialSupply - burnAmount);
    });

    it("Should revert if trying to burn more tokens than balance", async function () {
      const burnAmount = ethers.parseUnits("500", 9);
      await expect(sesh.connect(addr1).burn(burnAmount)).to.be.revertedWithCustomError(sesh,
          "ERC20InsufficientBalance");
    });
  });

  describe("Minting tokens", function () {
    it("Should revert when pool is not set", async function () {
      await expect(sesh.mint()).to.be.revertedWith("Shared: Zero-address is not permitted");
    }); 

    it("Should revert if totalSupply == supplyCap", async function () {
      const tx = await sesh.setPool(addr2.address);
      await tx.wait();
      await expect(sesh.mint()).to.be.revertedWith("SESH: Cap already reached");
    });

    it("Should mint to the pool if totalSupply < supplyCap", async function () {
      const burnAmount = ethers.parseUnits("500", 9);
      await sesh.burn(burnAmount);
      expect(await sesh.totalSupply()).to.equal(initialSupply - burnAmount);
      await sesh.setPool(addr2.address);
      expect(await sesh.pool()).to.equal(addr2.address);
      await sesh.mint();

      // The minted amount should be exactly (supplyCap - currentSupply)
      // Here supplyCap == initialSupply
      // currentSupply == initialSupply - burnAmount
      // So minted = burnAmount
      const poolBalance = await sesh.balanceOf(addr2.address);
      expect(poolBalance).to.equal(burnAmount);

      // After mint, totalSupply should be back to supplyCap
      expect(await sesh.totalSupply()).to.equal(initialSupply);
    });
  });
});

