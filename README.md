# Repository Deprecated
## This repository is now deprecated. The Session Token contracts now exist [here](https://github.com/session-foundation/session-token-contracts).This is in line with announcements from [Session](https://getsession.org/blog/introducing-the-session-technology-foundation) and the [OPTF](https://optf.ngo/blog/the-optf-and-session), indicating that the OPTF has handed over the stewardship of the Session Project and token to the [Session Technology Foundation](https://session.foundation), a Swiss-based foundation dedicated to advancing digital rights and innovation.


# Session Token Rewards Contract

This contract is designed to facilitate the integration and functioning of the
Session Token within the oxen network. The core of the codebase is now split
into two components: the existing C++ codebase, which handles various service
node responsibilities like uptime tracking, reward calculations, and other
duties; and the new smart contract system, which includes the Session Token
contract and this rewards contract.

The rewards contract manages the dynamics of nodes within the network. It
handles various crucial operations such as the admission of node operators
through stake deposits, broadcasting new node details across the network via
events/logs, managing the exit of stakers with an associated unlock period, and
the distribution of earned rewards. One of the key features of the rewards
contract is its use of BLS signatures. This technology enables the aggregation
of multiple signatures into a single, verifiable entity, ensuring that rewards
are distributed only when a consensus (e.g., 95% agreement within the network)
is achieved regarding the amount to be claimed.

## Building and Tests

There are 3 testing frameworks in use,

  - Javascript: Unit tests via Hardhat
  - C++: Integration tests via RPC over a devnet (like a local `hardhat node`)
  - Echidna: Fuzz testing of the smart contract over a devnet

### Javascript

Contracts can be compiled and tested against unit tests run by executing:

```
npm install -g pnpm            # If you don't have pnpm installed yet
pnpm install --frozen-lockfile # Install the dependencies
pnpm build                     # Build the JS unit-tests and Solidity contracts
pnpm test                      # Run the JS unit-tests
```

### C++

Integration tests require running a devnet first with the deployed smart
contracts followed by running the C++ tests which will communicate with the
given network. First setup the devnet:

```
make node         # Run the local devnet (note: This blocks the terminal)
make deploy-local # Deploy the smart contracts onto the devnet
```

Then execute the C++ tests by compilin and running, for example:

```
cd test/cpp/
cmake -B build -S .
cmake --build build --parallel --verbose

# Run the tests
./test/cpp/build/test/rewards_contract_Tests
```

### Echidna

Get [echidna](https://github.com/crytic/echidna) and place it onto your path.
Echidna also relies on [slither](https://github.com/crytic/slither) a static
analyzer that uses Python 3 and hence can be installed via
`python -m pip install slither-analyzer`.

Fuzz testing may then be run by executing:

```
make node # Run the local devnet (note: This blocks the terminal)
echidna . --contract ServiceNodeContributionEchidnaTest --config echidna-local.config.yml

# Or alternatively via the make target

make fuzz
```

We run Echidna in `assertion` testing mode which allows echidna to simulate
multiple senders (because our contracts can potentially use multiple wallets).
`property` testing mode simulates the transactions as if they were originating
from the smart contract which is not as useful for testing our contracts.

### Slither

You can run `slither` a static analyzer separately from Echidna by executing:

```
make analyze
```

## Scripts

- `scripts/attach-and-dump-sn-rewards-stats.js`

  Attaches to the `ServiceNodeRewards` instance specified in the script and
  dumps the current state of the contract. This script is RPC heavy as it
  scrapes contributors and service nodes information which currently is done
  with 1 request per entry.

  This script can be run via hardhat, e.g:

    npx hardhat run --network arbitrumSepolia scripts/attach-and-dump-sn-rewards-stats.js

