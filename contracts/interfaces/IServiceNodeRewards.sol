// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/BN256G1.sol";

interface IServiceNodeRewards {
    struct Contributor {
        address addr; // The address of the contributor
        uint256 stakedAmount; // The amount staked by the contributor
    }

    /// @notice Represents a service node in the network.
    struct ServiceNode {
        uint64 next;
        uint64 prev;
        address operator;
        BN256G1.G1Point pubkey;
        uint256 leaveRequestTimestamp;
        uint256 deposit;
        Contributor[] contributors;
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
    function IsActive() external view returns (bool);
    function liquidateTag() external view returns (bytes32);
    function liquidatorRewardRatio() external view returns (uint256);
    function maxContributors() external view returns (uint256);
    function nextServiceNodeID() external view returns (uint64);
    function poolShareOfLiquidationRatio() external view returns (uint256);
    function proofOfPossessionTag() external view returns (bytes32);
    function recipientRatio() external view returns (uint256);
    function recipients(address) external view returns (uint256 rewards, uint256 claimed);
    function removalTag() external view returns (bytes32);
    function rewardTag() external view returns (bytes32);
    function serviceNodes(uint64) external view returns (ServiceNode memory);
    function serviceNodeIDs(bytes memory) external view returns (uint64);
    function stakingRequirement() external view returns (uint256);
    function totalNodes() external view returns (uint256);

    // Function Signatures
	function updateRewardsBalance( address recipientAddress, uint256 recipientRewards, BLSSignatureParams calldata blsSignature, uint64[] memory ids) external;
    function claimRewards() external;
    function addBLSPublicKey(BN256G1.G1Point calldata blsPubkey, BLSSignatureParams calldata blsSignature, ServiceNodeParams calldata serviceNodeParams, Contributor[] calldata contributors) external;
    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) external;
    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, BN256G1.G1Point calldata blsPubkey, BLSSignatureParams calldata blsSignature, uint64[] memory ids) external;
    function removeBLSPublicKeyAfterWaitTime(uint64 serviceNodeID) external;
    function liquidateBLSPublicKeyWithSignature(uint64 serviceNodeID, BN256G1.G1Point calldata blsPubkey, BLSSignatureParams calldata blsSignature, uint64[] memory ids) external;
    function seedPublicKeyList(uint256[] calldata pkX, uint256[] calldata pkY, uint256[] calldata amounts) external;
    function serviceNodesLength() external view returns (uint256 count);
    function updateServiceNodesLength() external;
    function start() external;
}

