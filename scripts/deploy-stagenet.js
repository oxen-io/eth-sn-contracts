
require("./testnet-common.js")();

async function main() {
    // NOTE: We reuse the token address of the existing $SENT contract on stagenet
    const TOKEN_ADDRESS = "0x70c1f36C9cEBCa51B9344121D284D85BE36CD6bB";

    const args = {
      TOKEN_ADDRESS
    };
    await deployTestnetContracts("SENT Token", "SENT", args);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
