// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IServiceNodeContribution {
    function cancelNode() external;
}

// NOTE: Ensures that we cannot bypass `onlyOperator` by baiting a service node
// operator to execute an unrelated contract which forwards the interaction
// to the contribution contract (e.g. check we are not using tx.origin for
// authentication).
//
// See: https://docs.soliditylang.org/en/v0.8.20/security-considerations.html#tx-origin

contract TestModifierOnlyOperatorViaProxyContract {
    IServiceNodeContribution public immutable snContributionContract;

    constructor(address contractAddress) {
        snContributionContract = IServiceNodeContribution(contractAddress);
    }

    function proxyCancelNode() external {
        snContributionContract.cancelNode();
    }
}
