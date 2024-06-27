// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../RewardRatePool.sol";

contract TestnetRewardRatePool is RewardRatePool {
    using SafeERC20 for IERC20;
    // Function to set the lastPaidOutTime (onlyOwner)
    function setLastPaidOutTime(uint256 _lastPaidOutTime) external onlyOwner {
        lastPaidOutTime = _lastPaidOutTime;
    }

    event SENTWithdrawn(uint256 amount);

    // Function to withdraw SENT tokens back to the owner
    function withdrawSENT(uint256 amount) external onlyOwner {
        SENT.safeTransfer(owner(), amount);
        emit SENTWithdrawn(amount);
    }

}
