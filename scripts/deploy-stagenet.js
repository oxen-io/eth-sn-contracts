
require("./testnet-common.js")();

async function main() {
    // NOTE: We reuse the token address of the existing $SENT contract on stagenet
    await deployTestnetContracts("SENT Token", "SENT", /*tokenAddress*/ "0x70c1f36C9cEBCa51B9344121D284D85BE36CD6bB");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
