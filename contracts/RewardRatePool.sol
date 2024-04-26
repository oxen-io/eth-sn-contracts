// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Reward Rate Pool Contract
 * @dev Implements reward distribution based on a fixed annual interest rate.
 */
contract RewardRatePool {
    using SafeERC20 for IERC20;

    // solhint-disable-next-line var-name-mixedcase
    IERC20  public immutable SENT;
    address public immutable beneficiary;
    uint256 public           totalPaidOut;
    uint256 public           lastPaidOutTime;
    uint64  public constant  ANNUAL_INTEREST_RATE = 145; // 14.5% in tenths of a percent
    uint64  public constant  BASIS_POINTS         = 1000; // Basis points for percentage calculation

    /**
     * @dev Sets the initial beneficiary and SENT token address.
     * @param _beneficiary Address that will receive the interest payouts.
     * @param _sent Address of the SENT ERC20 token contract.
     */
    constructor(address _beneficiary, address _sent) {
        beneficiary     = _beneficiary;
        lastPaidOutTime = block.timestamp;
        SENT            = IERC20(_sent);
    }

    // EVENTS
    event FundsReleased(uint256 amount);

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @dev Calculates and releases the due interest payout to the beneficiary.
     * Updates the total paid out and the last payout time.
     */
    function payoutReleased() public {
        uint256 newTotalPaidOut  = calculateReleasedAmount(block.timestamp);
        uint256 released         = newTotalPaidOut - totalPaidOut;
        totalPaidOut             = newTotalPaidOut;
        lastPaidOutTime          = block.timestamp;
        SENT.safeTransfer(beneficiary, released);
        emit FundsReleased(released);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @dev Returns the block reward for a 2 minutes block at a certain timestamp.
     * @param timestamp The timestamp of the block.
     * @return The calculated block reward.
     */
    function rewardRate(uint256 timestamp) public view returns (uint256) {
        uint256 alreadyReleased = calculateReleasedAmount(timestamp);
        uint256 totalDeposited = calculateTotalDeposited();
        return calculateInterestAmount(totalDeposited - alreadyReleased, 2 minutes);
    }

    /**
     * @dev Calculates the total amount of SENT tokens deposited in the contract.
     * @return The sum of SENT tokens currently held by the contract and the total amount previously paid out.
     */
    function calculateTotalDeposited() public view returns (uint256) {
        return SENT.balanceOf(address(this)) + totalPaidOut;
    }

    /**
     * @dev Calculates the amount of SENT tokens released up to a specific timestamp.
     * @param timestamp The timestamp until which to calculate the released amount.
     * @return The calculated amount of SENT tokens released.
     */
    function calculateReleasedAmount(uint256 timestamp) public view returns (uint256) {
        uint256 timeElapsed = timestamp - lastPaidOutTime;
        return totalPaidOut + calculateInterestAmount(SENT.balanceOf(address(this)), timeElapsed);
    }

    /**
     * @dev Calculates 14.5% annual interest for a given balance and time period.
     * @param balance The principal balance to calculate interest on.
     * @param timeElapsed The time period over which to calculate interest.
     * @return The calculated interest amount.
     */
    function calculateInterestAmount(uint256 balance, uint256 timeElapsed) public pure returns (uint256) {
        return balance * ANNUAL_INTEREST_RATE * timeElapsed / (BASIS_POINTS * 365 days);
    }
}

