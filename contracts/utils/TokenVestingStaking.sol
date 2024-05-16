// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../libraries/Shared.sol";
import "../interfaces/ITokenVestingStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenVestingStaking
 * @dev A token holder contract that that vests its balance of any ERC20 token to the beneficiary.
 *      Validator lockup - stakable. Nothing unlocked until end of contract where everything
 *      unlocks at once. All funds can be staked during the vesting period.
 *      If revoked send all funds to revoker and block beneficiary releases indefinitely.
 *      Any staked funds at the moment of revocation can be retrieved by the revoker upon unstaking.
 *
 *      The vesting schedule is time-based (i.e. using block timestamps as opposed to e.g. block numbers), and
 *      is therefore sensitive to timestamp manipulation (which is something miners can do, to a certain degree).
 *      Therefore, it is recommended to avoid using short time durations (less than a minute).
 *
 */
contract TokenVestingStaking is ITokenVestingStaking, Shared {
    using SafeERC20 for IERC20;

    // beneficiary of tokens after they are released. It can be transferrable.
    address public beneficiary;
    bool public immutable transferableBeneficiary;
    // the revoker who can cancel the vesting and withdraw any unvested tokens
    address public revoker;

    // Durations and timestamps are expressed in UNIX time, the same units as block.timestamp.
    uint256 public immutable start;
    uint256 public immutable end;

    // solhint-disable-next-line var-name-mixedcase
    IERC20 public immutable SENT;

    // The contract that holds the reference addresses for staking purposes.
    IServiceNodeRewards public immutable stakingRewardsContract;

    bool public revoked;

    /// @notice Represents ours service nodes in the network.
    struct ServiceNode {
        uint64 serviceNodeID;
        uint256 deposit;
    }
    ServiceNode[] public investorServiceNodes;

    /**
     * @param beneficiary_ address of the beneficiary to whom vested tokens are transferred
     * @param revoker_   the person with the power to revoke the vesting. Address(0) means it is not revocable.
     * @param start_ the unix time when the beneficiary can start staking the tokens.
     * @param end_ the unix time of the end of the vesting period, everything withdrawable after
     * @param transferableBeneficiary_ whether the beneficiary address can be transferred
     * @param stakingRewardsContract_ the SENT staking rewads contract that can be interacted with
     * @param sent_ the SENT token address.
     */
    constructor(
        address beneficiary_,
        address revoker_,
        uint256 start_,
        uint256 end_,
        bool transferableBeneficiary_,
        IServiceNodeRewards stakingRewardsContract_,
        IERC20 sent_
    ) nzAddr(beneficiary_) nzAddr(address(stakingRewardsContract_)) nzAddr(address(sent_)) {
        require(start_ <= end_, "Vesting: start_ after end_");
        require(block.timestamp < start_, "Vesting: start before current time");

        beneficiary = beneficiary_;
        revoker = revoker_;
        start = start_;
        end = end_;
        transferableBeneficiary = transferableBeneficiary_;
        stakingRewardsContract = stakingRewardsContract_;
        SENT = sent_;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Adds a BLS public key to the list of service nodes. Requires a proof of possession BLS signature to prove user controls the public key being added
     * @param blsPubkey - 64 bytes of the bls public key
     * @param blsSignature - 128 byte signature
     * @param serviceNodeParams - Service node public key, signature proving ownership of public key and fee that operator is charging
     */
    function addBLSPublicKey(BN256G1.G1Point calldata blsPubkey,
                             IServiceNodeRewards.BLSSignatureParams calldata blsSignature,
                             IServiceNodeRewards.ServiceNodeParams calldata serviceNodeParams) external
        onlyBeneficiary
        notRevoked
        afterStart
    {
        uint256 stakingRequirement = stakingRewardsContract.stakingRequirement();
        uint64 serviceNodeID       = stakingRewardsContract.nextServiceNodeID();
        investorServiceNodes.push(ServiceNode(serviceNodeID, stakingRequirement));
        SENT.approve(address(stakingRewardsContract), stakingRequirement);

        // NOTE: Pass empty array, the contract will assume sender (this contract) as operator.
        IServiceNodeRewards.Contributor[] memory contributors = new IServiceNodeRewards.Contributor[](0);
        stakingRewardsContract.addBLSPublicKey(blsPubkey, blsSignature, serviceNodeParams, contributors);
    }

    /**
     * @notice Starts the process for removing a Service Node
     * @param serviceNodeID the identifier of the node which is being removed from network
     */
    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) external onlyBeneficiary notRevoked afterStart {
        stakingRewardsContract.initiateRemoveBLSPublicKey(serviceNodeID);
    }

    /**
     * @notice Gets rewards from staking and transfers to beneficiary
     */
    function claimRewards() external onlyBeneficiary notRevoked afterStart {
        uint256 unstaked = 0;
        uint256 length = investorServiceNodes.length;
        for (uint256 i = 1; i < length + 1; i++) {
            IServiceNodeRewards.ServiceNode memory sn = stakingRewardsContract.serviceNodes(investorServiceNodes[i - 1].serviceNodeID);
            if (sn.deposit == 0) {
                unstaked += investorServiceNodes[i - 1].deposit;

                // Remove service node from the array by swapping it with the last element and then popping the array
                investorServiceNodes[i - 1] = investorServiceNodes[length - 1];
                investorServiceNodes.pop();

                // Adjust loop variables since we modified the array
                i--;
                length--;
            }
        }

        uint256 balanceBeforeClaiming = SENT.balanceOf(address(this));
        stakingRewardsContract.claimRewards();
        uint256 balanceAfterClaiming = SENT.balanceOf(address(this)) - unstaked;

        uint256 amount = balanceAfterClaiming > balanceBeforeClaiming ? balanceAfterClaiming - balanceBeforeClaiming: 0;

        SENT.safeTransfer(beneficiary, amount);
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     * @param token ERC20 token which is being vested.
     */
    function release(IERC20 token) external override onlyBeneficiary notRevoked {
        uint256 unreleased = _releasableAmount(token);
        require(unreleased > 0, "Vesting: no tokens are due");

        emit TokensReleased(token, unreleased);

        token.safeTransfer(beneficiary, unreleased);
    }

    /**
     * @notice Allows the revoker to revoke the vesting and stop the beneficiary from releasing any
     *         tokens if the vesting period has not been completed. Any staked tokens at the time of
     *         revoking can be retrieved by the revoker upon unstaking via `retrieveRevokedFunds`.
     * @param token ERC20 token which is being vested.
     */
    function revoke(IERC20 token) external override onlyRevoker notRevoked {
        require(block.timestamp <= end, "Vesting: vesting expired");

        uint256 balance    = token.balanceOf(address(this));
        uint256 unreleased = _releasableAmount(token);
        uint256 refund     = balance - unreleased;
        revoked            = true;

        emit TokenVestingRevoked(token, refund);
        token.safeTransfer(revoker, refund);
    }

    /**
     * @notice Allows the revoker to retrieve tokens that have been unstaked after the revoke
     *         function has been called. Safeguard mechanism in case of unstaking happening
     *         after revoke, otherwise funds would be locked.
     * @param token ERC20 token which is being vested.
     */
    function retrieveRevokedFunds(IERC20 token) external override onlyRevoker {
        require(revoked, "Vesting: token not revoked");
        uint256 balance = token.balanceOf(address(this));

        token.safeTransfer(revoker, balance);
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     * @param token ERC20 token which is being vested.
     */
    function _releasableAmount(IERC20 token) private view returns (uint256) {
        return block.timestamp < end ? 0 : token.balanceOf(address(this));
    }

    /// @dev    Allow the beneficiary to be transferred to a new address if needed
    function transferBeneficiary(address beneficiary_) external override onlyBeneficiary nzAddr(beneficiary_) {
        require(transferableBeneficiary, "Vesting: beneficiary not transferrable");
        emit BeneficiaryTransferred(beneficiary, beneficiary_);
        beneficiary = beneficiary_;
    }

    /// @dev    Allow the revoker to be transferred to a new address if needed
    function transferRevoker(address revoker_) external override onlyRevoker nzAddr(revoker_) {
        emit RevokerTransferred(revoker, revoker_);
        revoker = revoker_;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @return the beneficiary address
     */
    function getBeneficiary() external view override returns (address) {
        return beneficiary;
    }

    /**
     * @return the revoker address
     */
    function getRevoker() external view override returns (address) {
        return revoker;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                      Modifiers                           //
    //                                                          //
    //////////////////////////////////////////////////////////////
    /**
     * @dev Ensure that the caller is the beneficiary address
     */
    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "Vesting: not the beneficiary");
        _;
    }

    /**
     * @dev Ensure that the caller is the revoker address
     */
    modifier onlyRevoker() {
        require(msg.sender == revoker, "Vesting: not the revoker");
        _;
    }

    modifier notRevoked() {
        require(!revoked, "Vesting: token revoked");
        _;
    }

    modifier afterStart() {
        require(block.timestamp >= start, "Vesting: not started");
        _;
    }
}
