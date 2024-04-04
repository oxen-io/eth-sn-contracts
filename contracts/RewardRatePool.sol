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
    uint64 public constant ANNUAL_INTEREST_RATE = 145; // 14.5% in tenths of a percent
    uint64 public constant BASIS_POINTS = 1000; // Basis points for percentage calculation

    constructor(address _beneficiary, address _sent) {
        beneficiary = _beneficiary;
        lastPaidOutTime = block.timestamp;
        SENT = IERC20(_sent);
    }

    // EVENTS
    event FundsReleased(uint256 amount);

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    // Calculate and pay out interest, then update the timestamp and total paid out
    function payoutReleased() public {
        uint256 released = calculateReleasedAmount(block.timestamp);
        totalPaidOut += released;
        SENT.safeTransfer(beneficiary, released);
        emit FundsReleased(released);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function rewardRate(uint256 timestamp) public view returns (uint256) {
        uint256 alreadyReleased = calculateReleasedAmount(timestamp);
        uint256 totalDeposited = calculateTotalDeposited();
        return calculateInterestAmount(totalDeposited - alreadyReleased, 2 minutes);
    }

    function calculateTotalDeposited() public view returns (uint256) {
        return SENT.balanceOf(address(this)) + totalPaidOut;
    }

    function calculateReleasedAmount(uint256 timestamp) public view returns (uint256) {
        uint256 timeElapsed = timestamp - lastPaidOutTime;
        return totalPaidOut + calculateInterestAmount(SENT.balanceOf(address(this)), timeElapsed);
    }

    function calculateInterestAmount(uint256 balance, uint256 timeElapsed) public pure returns (uint256) {
        return balance * ANNUAL_INTEREST_RATE * timeElapsed / (BASIS_POINTS * 365 days);
    }
}

