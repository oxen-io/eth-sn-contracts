// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardRatePool {
    using SafeERC20 for IERC20;

    // solhint-disable-next-line var-name-mixedcase
    IERC20 public immutable SENT;

    address immutable public beneficiary;
    uint256 public totalPaidOut;
    uint256 public lastPaidOutTime;
    uint256 public constant ANNUAL_INTEREST_RATE = 145; // 14.5% in tenths of a percent
    uint256 public constant BASIS_POINTS = 1000; // Basis points for percentage calculation

    constructor(address _beneficiary, address _sent) {
        beneficiary = _beneficiary;
        lastPaidOutTime = block.timestamp;
        SENT = IERC20(_sent);
    }

    function calculateTotalDeposited() public view returns (uint256) {
        return SENT.balanceOf(address(this)) + totalPaidOut;
    }

    // Calculate and pay out interest, then update the timestamp and total paid out
    function payoutReleased() public {
        require(block.timestamp > lastPaidOutTime, "Cannot pay out yet.");
        uint256 totalDeposited = calculateTotalDeposited();
        uint256 timeElapsed = block.timestamp - lastPaidOutTime;
        lastPaidOutTime = block.timestamp;
        uint256 released = (totalDeposited - totalPaidOut) * ANNUAL_INTEREST_RATE * timeElapsed / (BASIS_POINTS * 365 days);
        totalPaidOut += released;
        SENT.safeTransfer(beneficiary, released);
    }

    function rewardRate(uint256 timestamp) public view returns (uint256) {
        uint256 totalDeposited = calculateTotalDeposited();
        uint256 timeElapsed = timestamp - lastPaidOutTime;
        uint256 alreadyReleased = totalPaidOut + (totalDeposited - totalPaidOut) * ANNUAL_INTEREST_RATE * timeElapsed / (BASIS_POINTS * 365 days);
        return (totalDeposited - alreadyReleased) * ANNUAL_INTEREST_RATE * 2 minutes / (BASIS_POINTS * 365 days);
    }
}

