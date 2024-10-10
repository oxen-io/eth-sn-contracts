// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "../ServiceNodeRewards.sol";

contract TestnetServiceNodeRewards is ServiceNodeRewards {
    // NOTE: Admin function to remove node by ID for stagenet debugging
    function requestRemoveNodeBySNID(uint64[] calldata ids) external onlyOwner {
        uint256 idsLength = ids.length;
        for (uint256 i = 0; i < idsLength; ) {
            uint64 serviceNodeID                        = ids[i];
            IServiceNodeRewards.ServiceNode memory node = this.serviceNodes(serviceNodeID);
            require(node.operator != address(0));
            _initiateRemoveBLSPublicKey(serviceNodeID, node.operator);
            unchecked { i += 1; }
        }
    }

    function removeNodeBySNID(uint64[] calldata ids) external onlyOwner {
        uint256 idsLength = ids.length;
        for (uint256 i = 0; i < idsLength; ) {
            uint64 serviceNodeID                        = ids[i];
            IServiceNodeRewards.ServiceNode memory node = this.serviceNodes(serviceNodeID);
            require(node.operator != address(0));
            _removeBLSPublicKey(serviceNodeID, node.deposit);
            unchecked { i += 1; }
        }
    }
}
