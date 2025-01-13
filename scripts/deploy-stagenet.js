
require("./testnet-common.js")();

async function main() {
    // NOTE: We reuse the token address of the existing $SESH contract on stagenet
    const TOKEN_ADDRESS = "0x7D7fD4E91834A96cD9Fb2369E7f4EB72383bbdEd";

    const args = {
      TOKEN_ADDRESS
    };
    await deployTestnetContracts("SESH Token", "SESH", args);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
