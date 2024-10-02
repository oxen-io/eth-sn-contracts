// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IServiceNodeRewards.sol";
import "../interfaces/IServiceNodeContributionFactory.sol";
import "../interfaces/IServiceNodeContribution.sol";

interface ITokenVestingStaking {

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                       Events                             //
    //                                                          //
    //////////////////////////////////////////////////////////////

    event TokensReleased        (IERC20 indexed token, uint256 amount);
    event TokenVestingRevoked   (IERC20 indexed token, uint256 refund);
    event BeneficiaryTransferred(address oldBeneficiary, address newBeneficiary);
    event RevokerTransferred    (address oldRevoker, address newRevoker);

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                     Variables                            //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Address configured to receive tokens after they've vested from
    /// the contract. The beneficiary is transferable if the contract was
    /// deployed with the `transferableBeneficiary` enabled.
    function beneficiary() external view returns (address);

    /// @notice Indicates if the beneficiary is transferable to a new address or
    /// not.
    function transferableBeneficiary() external view returns (bool);

    /// @notice Start time of the contract's vesting period denoted as a unix
    /// timestamp
    function start() external view returns (uint256);

    /// @notice End time of the contract's vesting period denoted as a unix
    /// timestamp
    function end() external view returns (uint256);

    /// @notice The token that the contract is vesting to the investor.
    function SENT() external view returns (IERC20);

    /// @notice The contract that accepts investor tokens for staking
    function rewardsContract() external view returns (IServiceNodeRewards);

    /// @notice The contract that deploys multi-contributor contracts that the
    /// investor can stake to.
    function snContribFactory() external view returns (IServiceNodeContributionFactory);

    /// @notice Address that has permissions to halt the vesting process and
    /// withdraw the tokens. The revoker also has permissions to access admin
    /// functions of the contract.
    function revoker() external view returns (address);

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                 Rewards contract functions               //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Adds a BLS public key to the list of service nodes. Requires
    /// a proof of possession BLS signature to prove user controls the public
    /// key being added.
    ///
    /// @param blsPubkey 64 byte BLS public key for the service node.
    /// @param blsSignature 128 byte BLS proof of possession signature that
    /// proves ownership of the `blsPubkey`.
    /// @param serviceNodeParams The service node to add including the ed25519
    /// public key and signature that proves ownership of the private component
    /// of the public key and the desired fee the operator is charging.
    /// @param addrToReceiveRewards Address that should receive the staking rewards
    function addBLSPublicKey(
        BN256G1.G1Point calldata blsPubkey,
        IServiceNodeRewards.BLSSignatureParams calldata blsSignature,
        IServiceNodeRewards.ServiceNodeParams calldata serviceNodeParams,
        address addrToReceiveRewards
    ) external;

    /// @notice Initiates a request for the service node to leave the network by
    /// their service node ID.
    ///
    /// @param serviceNodeID The ID of the service node to be removed.
    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) external;

    /// @notice Retrieves the unlocked balance from exited/deregistered nodes
    /// back into this investor's contract.
    function claimRewards() external;

    /// @notice Claim a specific amount of unlocked balance from
    /// exited/deregistered nodes back into this investor's contract.
    function claimRewards(uint256 amount) external;

    //////////////////////////////////////////////////////////////
    //                                                          //
    //         Multi-contributor SN contract functions          //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function contributeFunds(address snContribAddr,
                             uint256 amount,
                             address addrToReceiveRewards) external;

    /// @notice Withdraw the contribution that has been made prior to a
    /// multi-contributor contract in `contributeFunds` returning the funds
    /// back to this investor's contract.
    ///
    /// This is only valid if the multi-contribution contract has not finalised
    /// yet or has already been reset.
    ///
    /// - If it has been finalised the funds have been transferred to the
    ///   rewards contract in which they must exit the node to reclaim their
    ///   funds back to the investor's contract.
    ///
    /// - If the contract has been reset the funds have been returned back to
    ///   this contract already.
    function withdrawContribution(address snContribAddr) external;

    /// @notice Allows the revoker to change the multi-contributor factory which
    /// determines if contribution addresses are valid.
    /// @param factoryAddr ServiceNodeContributionFactory address to update.
    function updateContributionFactory(address factoryAddr) external;

    //////////////////////////////////////////////////////////////
    //                                                          //
    //             Investor contract functions                  //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Transfers vested tokens to beneficiary.
    /// @param token ERC20 token which is being vested.
    function release(IERC20 token) external;

    /// @notice Allows the revoker to revoke the vesting and stop the beneficiary from releasing any
    ///         tokens if the vesting period has not been completed. Any staked tokens at the time of
    ///         revoking can be retrieved by the revoker upon unstaking via `retrieveRevokedFunds`.
    /// @param token ERC20 token which is being vested.
    function revoke(IERC20 token) external;

    /// @notice Allows the revoker to retrieve tokens that have been unstaked after the revoke
    ///         function has been called. Safeguard mechanism in case of unstaking happening
    ///         after revoke, otherwise funds would be locked.
    /// @param token ERC20 token which is being vested.
    function retrieveRevokedFunds(IERC20 token) external;

    /// @dev Allow the beneficiary to be transferred to a new address if needed
    function transferBeneficiary(address beneficiary_) external;

    /// @dev Allow the revoker to be transferred to a new address if needed
    function transferRevoker(address revoker_) external;

}
