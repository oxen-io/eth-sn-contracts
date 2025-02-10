// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/BN256G1.sol";

interface IServiceNodeRewards {
    struct Staker {
        address addr;        // Address that is contributing the stake
        address beneficiary; // Address rewards are paid out to
    }

    struct Contributor {
        Staker staker;        // Address details for contributor
        uint256 stakedAmount; // Amount staked by the contributor
    }

    struct ReservedContributor {
        address addr;   // Address that is reserving a contribution amount
        uint256 amount; // Amount that the address is reserving
    }

    struct SeedServiceNode {
        BN256G1.G1Point blsPubkey;
        uint256         ed25519Pubkey;
        uint256         addedTimestamp;
        Contributor[]   contributors;
    }

    /// @notice Represents a node in the network.
    struct ServiceNode {
        uint64          next;
        uint64          prev;
        address         operator;
        BN256G1.G1Point blsPubkey;
        uint256         addedTimestamp;
        /// Timestamp of the first time a leave request was requeste on the node
        uint256         leaveRequestTimestamp;

        /// Timestamp of the latest time a leave request was requested on the
        /// node. Multiple leave requests are permitted for node in the event
        /// that the Session network rejects the request for various possible
        /// reasons.
        ///
        /// Subsequent leave requests can be overlapped to get the network to
        /// re-emit the event to be witnessed by the Session network again.
        uint256         latestLeaveRequestTimestamp;
        uint256         deposit;
        Contributor[]   contributors;
        uint256         ed25519Pubkey;
    }

    /// @notice Represents a recipient of rewards, how much they can claim and how much previously claimed.
    struct Recipient {
        uint256 rewards;
        uint256 claimed;
    }

    struct BLSSignatureParams {
        uint256 sigs0;
        uint256 sigs1;
        uint256 sigs2;
        uint256 sigs3;
    }

    struct ServiceNodeParams {
        uint256 serviceNodePubkey;
        uint256 serviceNodeSignature1;
        uint256 serviceNodeSignature2;
        uint16  fee;
    }
    // Public Variables
    function aggregatePubkey() external view returns (BN256G1.G1Point memory);
    function blsNonSignerThreshold() external view returns (uint256);
    function designatedToken() external view returns (IERC20);
    function foundationPool() external view returns (IERC20);
    function isStarted() external view returns (bool);
    function liquidateTag() external view returns (bytes32);
    function liquidatorRewardRatio() external view returns (uint256);
    function maxContributors() external view returns (uint256);
    function nextServiceNodeID() external view returns (uint64);
    function poolShareOfLiquidationRatio() external view returns (uint256);
    function proofOfPossessionTag() external view returns (bytes32);
    function recipientRatio() external view returns (uint256);
    function recipients(address) external view returns (uint256 rewards, uint256 claimed);
    function exitTag() external view returns (bytes32);
    function rewardTag() external view returns (bytes32);
    function serviceNodes(uint64) external view returns (ServiceNode memory);
    function serviceNodeIDs(bytes memory) external view returns (uint64);
    function allServiceNodeIDs() external view returns (uint64[] memory ids, BN256G1.G1Point[] memory pubkeys);
    function stakingRequirement() external view returns (uint256);
    function totalNodes() external view returns (uint256);

    // Function Signatures
    function updateRewardsBalance(
        address recipientAddress,
        uint256 recipientRewards,
        BLSSignatureParams calldata blsSignature,
        uint64[] memory ids
    ) external;

    function claimRewards() external;

    function claimRewards(uint256 amount) external;

    function addBLSPublicKey(
        BN256G1.G1Point memory blsPubkey,
        BLSSignatureParams memory blsSignature,
        ServiceNodeParams memory serviceNodeParams,
        Contributor[] memory contributors
    ) external;
    function validateProofOfPossession(BN256G1.G1Point memory blsPubkey, BLSSignatureParams memory blsSignature, address caller, uint256 serviceNodePubkey) external;
    function initiateExitBLSPublicKey(uint64 serviceNodeID) external;
    function exitBLSPublicKeyWithSignature(
        BN256G1.G1Point calldata blsPubkey,
        uint256 timestamp,
        BLSSignatureParams calldata blsSignature,
        uint64[] memory ids
    ) external;
    function exitBLSPublicKeyAfterWaitTime(uint64 serviceNodeID) external;
    function liquidateBLSPublicKeyWithSignature(
        BN256G1.G1Point calldata blsPubkey,
        uint256 timestamp,
        BLSSignatureParams calldata blsSignature,
        uint64[] memory ids
    ) external;
    function seedPublicKeyList(SeedServiceNode[] calldata nodes) external;
    function rederiveTotalNodesAndAggregatePubkey() external;
    function start() external;
}
