
require("./testnet-common.js")();

async function main() {
    await deployTestnetContracts("SESH Token (devnet v3)", "DEVSESH3");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
