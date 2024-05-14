require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');

require("dotenv/config");

const arb_sepolia_account = process.env.ARB_SEPOLIA_PRIVATE_KEY ? [process.env.ARB_SEPOLIA_PRIVATE_KEY] : [];
const arb_account = process.env.ARB_PRIVATE_KEY ? [process.env.ARB_PRIVATE_KEY] : [];

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
      arbitrum: {
         url: "https://arb1.arbitrum.io/rpc",
         chainId: 42161,
         accounts: arb_account,
      },
      sepoliaarbitrum: {
         url: "https://sepolia-rollup.arbitrum.io/rpc",
         chainId: 421614,
         accounts: arb_sepolia_account,
      }
  },
  solidity: {
    version: '0.8.20',
    settings: {
      optimizer: {
        enabled: true,
        runs: 800,
      },
      metadata: {
        // do not include the metadata hash, since this is machine dependent
        // and we want all generated code to be deterministic
        // https://docs.soliditylang.org/en/v0.7.6/metadata.html
        bytecodeHash: 'none',
      },
    },
  },
};

