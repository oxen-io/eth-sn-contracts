// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../ServiceNodeRewards.sol";

contract TestnetServiceNodeRewards is ServiceNodeRewards {
    // NOTE: Admin function to remove node by ID for stagenet debugging
    function removeNodeBySNID(uint64[] calldata ids) external onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            uint64 serviceNodeID = ids[i];
            IServiceNodeRewards.ServiceNode memory node = this.serviceNodes(serviceNodeID);
            require(node.operator != address(0));
            _removeBLSPublicKey(serviceNodeID, node.deposit);
        }
    }
}
