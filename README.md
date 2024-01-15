# Session Token Rewards Contract

This contract is designed to facilitate the integration and functioning of the Session Token within the oxen network. The core of the codebase is now split into two components: the existing C++ codebase, which handles various service node responsibilities like uptime tracking, reward calculations, and other duties; and the new smart contract system, which includes the Session Token contract and this rewards contract.

The rewards contract manages the dynamics of nodes within the network. It handles various crucial operations such as the admission of node operators through stake deposits, broadcasting new node details across the network via events/logs, managing the exit of stakers with an associated unlock period, and the distribution of earned rewards. One of the key features of the rewards contract is its use of BLS signatures. This technology enables the aggregation of multiple signatures into a single, verifiable entity, ensuring that rewards are distributed only when a consensus (e.g., 95% agreement within the network) is achieved regarding the amount to be claimed.

## Building and tests
There are 2 components to the tests, the regular hardhat javascript tests and c++ tests mimicking the stack our network code has.

### Running Javascript tests
from the root directory
```
yarn
yarn build
yarn test
```

### Running C++ tests
This requires simultaneously running a terminal for the hardhat node and another for running the tests. In the first terminal from the root directory run
```
make node
```

Then from another terminal while the node is still running

```
make deploy-local
```

This will deploy our rewards contract to the node. This will need to be done every time the c++ tests are run

Next compile the c++ tests with

```
cd test/cpp/
mkdir build
cd build
cmake ..
make
```

which should create a test binary that you can run. Any changes to the c++ tests will need a recompile
```
./test/cpp/build/test/rewards_contract_Tests

```
