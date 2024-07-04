// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../ServiceNodeRewards.sol";

contract TestnetServiceNodeRewards is ServiceNodeRewards {
    // New function for owner to remove nodes without BLS signature validation
    function removeNodeByOwner(uint64 serviceNodeID) external onlyOwner {
        IServiceNodeRewards.ServiceNode memory node = this.serviceNodes(serviceNodeID);
        _removeBLSPublicKey(serviceNodeID, node.deposit);
    }
}
