
require("./testnet-common.js")();

async function main() {
    await deployTestnetContracts("SENT Token", "SENT");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
