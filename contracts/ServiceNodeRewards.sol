// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./libraries/Pairing.sol";

/// @title Service Node Rewards Contract
/// @notice This contract manages the rewards and public keys for service nodes.
contract ServiceNodeRewards is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    bool public IsActive = false;

    IERC20 public immutable designatedToken;
    IERC20 public immutable foundationPool;

    uint64 public nextServiceNodeID = 1;
    uint64 public constant LIST_END = type(uint64).max;
    uint256 public constant MAX_SERVICE_NODE_REMOVAL_WAIT_TIME = 30 days;

    uint256 public totalNodes = 0;
    uint256 public blsNonSignerThreshold = 0;
    uint256 public upperLimitNonSigners = 300;

    bytes32 immutable public proofOfPossessionTag;
    bytes32 immutable public rewardTag;
    bytes32 immutable public removalTag;
    bytes32 immutable public liquidateTag;

    uint256 stakingRequirement;
    uint256 immutable liquidatorRewardRatio;
    uint256 immutable poolShareOfLiquidationRatio;
    uint256 immutable recipientRatio;

    /// @notice Constructor for the Service Node Rewards Contract
    /// @param _token The token used for rewards
    /// @param _foundationPool The foundation pool for the token
    /// @param _stakingRequirement The staking requirement for service nodes
    /// @param _liquidatorRewardRatio The reward ratio for liquidators
    /// @param _poolShareOfLiquidationRatio The pool share ratio during liquidation
    /// @param _recipientRatio The recipient ratio for rewards
    constructor(address _token, address _foundationPool, uint256 _stakingRequirement, uint256 _liquidatorRewardRatio, uint256 _poolShareOfLiquidationRatio, uint256 _recipientRatio) Ownable(msg.sender) {
        if (_recipientRatio < 1) revert RecipientRewardsTooLow();
        proofOfPossessionTag = buildTag("BLS_SIG_TRYANDINCREMENT_POP");
        rewardTag = buildTag("BLS_SIG_TRYANDINCREMENT_REWARD");
        removalTag = buildTag("BLS_SIG_TRYANDINCREMENT_REMOVE");
        liquidateTag = buildTag("BLS_SIG_TRYANDINCREMENT_LIQUIDATE");

        designatedToken = IERC20(_token);
        foundationPool = IERC20(_foundationPool);
        stakingRequirement = _stakingRequirement;
        liquidatorRewardRatio = _liquidatorRewardRatio;
        poolShareOfLiquidationRatio = _poolShareOfLiquidationRatio;
        recipientRatio = _recipientRatio;

        serviceNodes[LIST_END].previous = LIST_END;
        serviceNodes[LIST_END].next = LIST_END;
    }

    /// @dev Builds a tag string using a base tag and contract-specific information. This is used when signing messages to prevent reuse of signatures across different domains (chains/functions/contracts)
    /// @param baseTag The base string for the tag.
    /// @return The constructed tag string.
    function buildTag(string memory baseTag) private view returns (bytes32) {
        return keccak256(bytes(abi.encodePacked(baseTag, block.chainid, address(this))));
    }

    /// @notice Represents a service node in the network.
    struct ServiceNode {
        uint64 next;
        uint64 previous;
        address recipient;
        BN256G1.G1Point pubkey;
        uint256 leaveRequestTimestamp;
        uint256 deposit;
    }

    /// @notice Represents a recipient of rewards, how much they can claim and how much previously claimed.
    struct Recipient {
        uint256 rewards;
        uint256 claimed;
    }

    mapping(uint64 => ServiceNode) public serviceNodes;
    mapping(address => Recipient) public recipients;
    mapping(bytes => uint64) public serviceNodeIDs;

    BN256G1.G1Point public aggregate_pubkey;

    struct Contributor {
        address addr; // The address of the contributor
        uint256 stakedAmount; // The amount staked by the contributor
    }

    // EVENTS
    event NewSeededServiceNode(uint64 indexed serviceNodeID, BN256G1.G1Point pubkey);
    event NewServiceNode( uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey, uint256 serviceNodePubkey, uint256 serviceNodeSignature, uint256 serviceNodeSignature2, uint16 fee,Contributor[] contributors);
    event RewardsBalanceUpdated(address indexed recipientAddress, uint256 amount, uint256 previousBalance);
    event RewardsClaimed(address indexed recipientAddress, uint256 amount);
    event NonSignersLimitUpdated(uint256 newRequirement);
    event ServiceNodeLiquidated(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event ServiceNodeRemoval(uint64 indexed serviceNodeID, address recipient, uint256 returnedAmount, BN256G1.G1Point pubkey);
    event ServiceNodeRemovalRequest(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event StakingRequirementUpdated(uint256 newRequirement);

    // ERRORS
    error RecipientAddressDoesNotMatch(address expectedRecipient, address providedRecipient, uint256 serviceNodeID);
    error BLSPubkeyAlreadyExists(uint64 serviceNodeID);
    error BLSPubkeyDoesNotMatch(uint64 serviceNodeID, uint256 pkX, uint256 pkY);
    error EarlierLeaveRequestMade(uint64 serviceNodeID, address recipient);
    error LeaveRequestTooEarly(uint64 serviceNodeID, uint256 timestamp, uint256 currenttime);
    error ServiceNodeDoesntExist(uint64 serviceNodeID);
    error InvalidBLSSignature();
    error InvalidBLSProofOfPossession();
    error ArrayLengthMismatch();
    error NullRecipient();
    error InsufficientBLSSignatures(uint256 numSigners, uint256 requiredSigners);
    error ContractNotActive();
    error ContractAlreadyActive();
    error RecipientRewardsTooLow();


    /// CLAIMING REWARDS
    /// This section contains all the functions necessary for a user to receive the rewards from the service node network. Process looks like follows:
    /// 1) User will go to service node network and request they sign an amount that they are allowed to claim. Each node will individually sign and user will aggregate the message
    /// 2) User will call updateRewardsBalance with an encoded message of the amount they are allowed to claim. This signature is checked over this message and the recipient structure is updated fo the amount they are allowed to claim
    /// 3) User will call claimRewards which will pay out their balance in the recipients struct

	/// @notice Updates the rewards balance for a given recipient, requires a BLS signature from the network
	/// @param recipientAddress The address of the recipient.
	/// @param recipientRewards The amount of rewards the recipient is allowed to claim.
	/// @param sigs0 First part of the signature.
	/// @param sigs1 Second part of the signature.
	/// @param sigs2 Third part of the signature.
	/// @param sigs3 Fourth part of the signature.
    /// @param ids An array of service node IDs that did not sign and to be excluded from aggregation.
	function updateRewardsBalance(
		address recipientAddress, 
		uint256 recipientRewards,
		uint256 sigs0,
		uint256 sigs1,
		uint256 sigs2,
		uint256 sigs3,
		uint64[] memory ids
	) public whenNotPaused {
        if (!IsActive) revert ContractNotActive();
        if (recipientAddress == address(0)) revert NullRecipient();
        if (ids.length > blsNonSignerThreshold) revert InsufficientBLSSignatures(serviceNodesLength() - ids.length, serviceNodesLength() - blsNonSignerThreshold);
        if (recipients[recipientAddress].rewards >= recipientRewards) revert RecipientRewardsTooLow();
		BN256G1.G1Point memory pubkey;
		for(uint256 i = 0; i < ids.length; i++) {
			pubkey = BN256G1.add(pubkey, serviceNodes[ids[i]].pubkey);
		}
		pubkey = BN256G1.add(aggregate_pubkey, BN256G1.negate(pubkey));
		BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
		bytes memory encodedMessage = abi.encodePacked(rewardTag, recipientAddress, recipientRewards);
		BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(encodedMessage)));
		if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSSignature();

		uint256 previousBalance = recipients[recipientAddress].rewards;
		recipients[recipientAddress].rewards = recipientRewards;
		emit RewardsBalanceUpdated(recipientAddress, recipientRewards, previousBalance);
	}


    /// @notice Builds a message for recipient reward calculation.
    /// @param recipientAddress The address of the recipient.
    /// @param balance The balance to be encoded in the message.
    /// @return The encoded message.
    function buildRecipientMessage(address recipientAddress, uint256 balance) public pure returns (bytes memory) {
        return abi.encode(recipientAddress, balance);
    }

    /// @dev Internal function to handle reward claims. Will transfer the available rewards worth of our token to claimingAddress
    /// @param claimingAddress The address claiming the rewards.
    function _claimRewards(address claimingAddress) internal {
        uint256 claimedRewards = recipients[claimingAddress].claimed;
        uint256 totalRewards = recipients[claimingAddress].rewards;
        uint256 amountToRedeem = totalRewards - claimedRewards;
        recipients[claimingAddress].claimed = totalRewards;
        SafeERC20.safeTransfer(designatedToken, claimingAddress, amountToRedeem);
        emit RewardsClaimed(claimingAddress, amountToRedeem);
    }

    /// @notice Allows users to claim their rewards. Main entry point for users claiming. Should be called after first updating rewards
    function claimRewards() public {
        _claimRewards(msg.sender);
    }

    /// MANAGING BLS PUBLIC KEY LIST
    /// This section contains all the functions necessary to add and remove service nodes from the service nodes linked list.
    /// The regular process for this will be for a new user to call

    /// @notice Adds a BLS public key to the list of service nodes. Requires a proof of possession BLS signature to prove user controls the public key being added
    /// @param pkX X-coordinate of the public key.
    /// @param pkY Y-coordinate of the public key.
    /// @param sigs0 First part of the proof of possession signature.
    /// @param sigs1 Second part of the proof of possession signature.
    /// @param sigs2 Third part of the proof of possession signature.
    /// @param sigs3 Fourth part of the proof of possession signature.
    function addBLSPublicKey(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint256 serviceNodePubkey, uint256 serviceNodeSignature) public whenNotPaused {
        _addBLSPublicKey(pkX, pkY, sigs0, sigs1, sigs2, sigs3, msg.sender, serviceNodePubkey, serviceNodeSignature);
    }

    /// @dev Internal function to add a BLS public key.
    /// @param pkX X-coordinate of the public key.
    /// @param pkY Y-coordinate of the public key.
    /// @param sigs0 First part of the signature.
    /// @param sigs1 Second part of the signature.
    /// @param sigs2 Third part of the signature.
    /// @param sigs3 Fourth part of the signature.
    /// @param recipient The address of the recipient associated with the public key.
    function _addBLSPublicKey(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, address recipient, uint256 serviceNodePubkey, uint256 serviceNodeSignature) internal {
        if (!IsActive) revert ContractNotActive();
        BN256G1.G1Point memory pubkey = BN256G1.G1Point(pkX, pkY);
        uint64 serviceNodeID = serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)];
        if(serviceNodeID != 0) revert BLSPubkeyAlreadyExists(serviceNodeID);
        validateProofOfPossession(pubkey, sigs0, sigs1, sigs2, sigs3, recipient, serviceNodePubkey);
        uint64 previous = serviceNodes[LIST_END].previous;

        /*serviceNodes[nextServiceNodeID] = ServiceNode(previous, recipient, pubkey, LIST_END);*/
        serviceNodes[previous].next = nextServiceNodeID;
        serviceNodes[nextServiceNodeID].previous = previous;
        serviceNodes[nextServiceNodeID].next = LIST_END;
        serviceNodes[nextServiceNodeID].pubkey = pubkey;
        serviceNodes[nextServiceNodeID].recipient = recipient;
        serviceNodes[nextServiceNodeID].deposit = stakingRequirement;
        serviceNodes[LIST_END].previous = nextServiceNodeID;

        serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)] = nextServiceNodeID;

        if (serviceNodes[LIST_END].next != LIST_END) {
            aggregate_pubkey = BN256G1.add(aggregate_pubkey, pubkey);
        } else {
            aggregate_pubkey = pubkey;
        }
        totalNodes++;
        updateBLSThreshold();
        Contributor[] memory contributors = new Contributor[](1);
        contributors[0] = Contributor(msg.sender, stakingRequirement);
        emit NewServiceNode( nextServiceNodeID, recipient, pubkey, serviceNodePubkey, serviceNodeSignature, serviceNodeSignature, 0, contributors);
        nextServiceNodeID++;
        SafeERC20.safeTransferFrom(designatedToken, recipient, address(this), stakingRequirement);
    }

    /// @notice Validates the proof of possession for a given BLS public key.
    /// @param pubkey The BLS public key.
    /// @param sigs0 First part of the proof of possession signature.
    /// @param sigs1 Second part of the proof of possession signature.
    /// @param sigs2 Third part of the proof of possession signature.
    /// @param sigs3 Fourth part of the proof of possession signature.
    function validateProofOfPossession(BN256G1.G1Point memory pubkey, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, address recipient, uint256 serviceNodePubkey) internal {
        BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(proofOfPossessionTag, pubkey.X, pubkey.Y, recipient, serviceNodePubkey))));
        BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSProofOfPossession();
    }

    /// @notice Initiates the removal of a BLS public key. This simply notifies the network that the node wishes to leave the network. There will be a delay before the network allows this node to exit gracefully. Should be called first and later once the network is happy for node to exis the user should call `removeBLSPublicKeyWithSignature` with a valid BLS signature returned by the network
    /// @param serviceNodeID The ID of the service node to be removed.
    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) public whenNotPaused {
        _initiateRemoveBLSPublicKey(serviceNodeID, msg.sender);
    }
        
    /// @notice Initiates the removal of a BLS public key.
    /// @param serviceNodeID The ID of the service node.
    /// @param recipient The address of the recipient associated with the service node.
    function _initiateRemoveBLSPublicKey(uint64 serviceNodeID, address recipient) internal {
        if (!IsActive) revert ContractNotActive();
        address serviceNodeRecipient = serviceNodes[serviceNodeID].recipient;
        if(serviceNodeRecipient != recipient) revert RecipientAddressDoesNotMatch(serviceNodeRecipient, recipient, serviceNodeID);
        if(serviceNodes[serviceNodeID].leaveRequestTimestamp != 0) revert EarlierLeaveRequestMade(serviceNodeID, recipient);
        serviceNodes[serviceNodeID].leaveRequestTimestamp = block.timestamp;
        emit ServiceNodeRemovalRequest(serviceNodeID, recipient, serviceNodes[serviceNodeID].pubkey);
    }

    /// @notice Removes a BLS public key using an aggregated BLS signature from the network.
    /// @param serviceNodeID The ID of the service node to be removed.
    /// @param sigs0 First part of the signature.
    /// @param sigs1 Second part of the signature.
    /// @param sigs2 Third part of the signature.
    /// @param sigs3 Fourth part of the signature.
    /// @param ids An array of service node IDs that did not sign and to be excluded from aggregation.
    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] memory ids) external whenNotPaused {
        if (!IsActive) revert ContractNotActive();
        if (ids.length > blsNonSignerThreshold) revert InsufficientBLSSignatures(serviceNodesLength() - ids.length, serviceNodesLength() - blsNonSignerThreshold);
        if (pkX != serviceNodes[serviceNodeID].pubkey.X || pkY != serviceNodes[serviceNodeID].pubkey.Y) revert BLSPubkeyDoesNotMatch(serviceNodeID, pkX, pkY);
        //Validating signature
        BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(removalTag, pkX, pkY))));
        BN256G1.G1Point memory pubkey;
        for(uint256 i = 0; i < ids.length; i++) {
            pubkey = BN256G1.add(pubkey, serviceNodes[ids[i]].pubkey);
        }
        pubkey = BN256G1.add(aggregate_pubkey, BN256G1.negate(pubkey));
        BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSSignature();

        _removeBLSPublicKey(serviceNodeID, serviceNodes[serviceNodeID].deposit);
    }

    /// @notice Removes a BLS public key after a specified wait time, this can be called without the BLS signature because the node has waited extra long   .
    /// @param serviceNodeID The ID of the service node to be removed.
    function removeBLSPublicKeyAfterWaitTime(uint64 serviceNodeID) external whenNotPaused {
        if (!IsActive) revert ContractNotActive();
        uint256 leaveRequestTimestamp = serviceNodes[serviceNodeID].leaveRequestTimestamp;
        if(leaveRequestTimestamp == 0) revert LeaveRequestTooEarly(serviceNodeID, leaveRequestTimestamp, block.timestamp);
        uint256 timestamp = leaveRequestTimestamp + MAX_SERVICE_NODE_REMOVAL_WAIT_TIME;
        if(block.timestamp <= timestamp) revert LeaveRequestTooEarly(serviceNodeID, timestamp, block.timestamp);
        _removeBLSPublicKey(serviceNodeID, serviceNodes[serviceNodeID].deposit);
    }

    /// @dev Internal function to remove a BLS public key. Updates the linked list to remove the node
    /// @param serviceNodeID The ID of the service node to be removed.
    function _removeBLSPublicKey(uint64 serviceNodeID, uint256 returnedAmount) internal {
        address serviceNodeRecipient = serviceNodes[serviceNodeID].recipient;
        uint64 previousServiceNode = serviceNodes[serviceNodeID].previous;
        uint64 nextServiceNode = serviceNodes[serviceNodeID].next;
        if (nextServiceNode == 0) revert ServiceNodeDoesntExist(serviceNodeID);

        serviceNodes[previousServiceNode].next = nextServiceNode;
        serviceNodes[nextServiceNode].previous = previousServiceNode;

        BN256G1.G1Point memory pubkey = BN256G1.G1Point(serviceNodes[serviceNodeID].pubkey.X, serviceNodes[serviceNodeID].pubkey.Y);

        aggregate_pubkey = BN256G1.add(aggregate_pubkey, BN256G1.negate(pubkey));

        delete serviceNodes[serviceNodeID];

        delete serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)];

        totalNodes--;
        updateBLSThreshold();

        emit ServiceNodeRemoval(serviceNodeID, serviceNodeRecipient, returnedAmount, pubkey);
    }

    /// @notice Liquidates a BLS public key using a signature. This function can be called by anyone if the network wishes for the node to be removed (ie from a dereg) without relying on the user to remove themselves
    /// @param serviceNodeID The ID of the service node to be liquidated.
    /// @param sigs0 First part of the signature.
    /// @param sigs1 Second part of the signature.
    /// @param sigs2 Third part of the signature.
    /// @param sigs3 Fourth part of the signature.
    function liquidateBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] memory ids) external whenNotPaused {
        if (!IsActive) revert ContractNotActive();
        if (ids.length > blsNonSignerThreshold) revert InsufficientBLSSignatures(serviceNodesLength() - ids.length, serviceNodesLength() - blsNonSignerThreshold);
        ServiceNode memory node = serviceNodes[serviceNodeID];
        if (pkX != node.pubkey.X || pkY != node.pubkey.Y) revert BLSPubkeyDoesNotMatch(serviceNodeID, pkX, pkY);
        //Validating signature
        {
            BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(liquidateTag, pkX, pkY))));
            BN256G1.G1Point memory pubkey;
            for(uint256 i = 0; i < ids.length; i++) {
                pubkey = BN256G1.add(pubkey, serviceNodes[ids[i]].pubkey);
            }
            pubkey = BN256G1.add(aggregate_pubkey, BN256G1.negate(pubkey));
            BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
            if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSSignature();
        }


        // Calculating how much liquidator is paid out
        uint256 ratioSum = poolShareOfLiquidationRatio + liquidatorRewardRatio + recipientRatio;
        emit ServiceNodeLiquidated(serviceNodeID, node.recipient, node.pubkey);
        uint256 deposit = node.deposit;

        uint256 liquidatorAmount = deposit * liquidatorRewardRatio / ratioSum;
        //TODO sean check c++ tests still work
        /*uint256 poolAmount = deposit * ceilDiv(poolShareOfLiquidationRatio, ratioSum;*/
        uint256 poolAmount = deposit * poolShareOfLiquidationRatio == 0 ? 0 : (poolShareOfLiquidationRatio - 1) / ratioSum + 1;

        _removeBLSPublicKey(serviceNodeID, deposit - liquidatorAmount - poolAmount);


        // Transfer funds to pool and liquidator
        if (liquidatorRewardRatio > 0)
            SafeERC20.safeTransfer(designatedToken, msg.sender, liquidatorAmount);
        if (poolShareOfLiquidationRatio > 0)
            SafeERC20.safeTransfer(designatedToken, address(foundationPool), poolAmount);
    }

    /// @notice Seeds the public key list with an initial set of keys. Only should be called before the hardfork by the foundation to ensure the public key list is ready to operate.
    /// @param pkX Array of X-coordinates for the public keys.
    /// @param pkY Array of Y-coordinates for the public keys.
    /// @param amounts Array of amounts that the service node has staked, associated with each public key.
    function seedPublicKeyList(uint256[] calldata pkX, uint256[] calldata pkY, uint256[] calldata amounts) public onlyOwner {
        if (pkX.length != pkY.length || pkX.length != amounts.length) revert ArrayLengthMismatch();
        uint64 lastServiceNodeID = serviceNodes[LIST_END].previous;
        bool firstServiceNode = serviceNodesLength() == 0;

        for(uint256 i = 0; i < pkX.length; i++) {
            BN256G1.G1Point memory pubkey = BN256G1.G1Point(pkX[i], pkY[i]);
            bytes memory pubkeybytes = BN256G1.getKeyForG1Point(pubkey);
            uint64 serviceNodeID = serviceNodeIDs[pubkeybytes];
            if(serviceNodeID != 0) revert BLSPubkeyAlreadyExists(serviceNodeID);

            /*serviceNodes[nextServiceNodeID] = ServiceNode(previous, recipient, pubkey, LIST_END);*/
            serviceNodes[lastServiceNodeID].next = nextServiceNodeID;
            serviceNodes[nextServiceNodeID].previous = lastServiceNodeID;
            serviceNodes[nextServiceNodeID].pubkey = pubkey;
            serviceNodes[nextServiceNodeID].deposit = amounts[i];

            serviceNodeIDs[pubkeybytes] = nextServiceNodeID;

            if (!firstServiceNode) {
                aggregate_pubkey = BN256G1.add(aggregate_pubkey, pubkey);
            } else {
                aggregate_pubkey = pubkey;
                firstServiceNode = false;
            }

            emit NewSeededServiceNode(nextServiceNodeID, pubkey);
            lastServiceNodeID = nextServiceNodeID;
            nextServiceNodeID++;
            totalNodes++;
        }

        serviceNodes[lastServiceNodeID].next = LIST_END;
        serviceNodes[LIST_END].previous = lastServiceNodeID;

        updateBLSThreshold();
    }

    /// @notice Counts the number of service nodes in the linked list.
    /// @return count The total number of service nodes in the list.
    function serviceNodesLength() public view returns (uint256 count) {
        uint64 currentNode = serviceNodes[LIST_END].next;
        count = 0;

        while (currentNode != LIST_END) {
            count++;
            currentNode = serviceNodes[currentNode].next;
        }

        return count;
    }

    /// @notice allows anyone to update the service nodes length variable
    function updateServiceNodesLength() public {
        totalNodes = serviceNodesLength();
    }

    /// @notice Updates the internal threshold for how many non signers an aggregate signature can contain before being invalid
    function updateBLSThreshold() internal {
        if (totalNodes > 900) {
            blsNonSignerThreshold = upperLimitNonSigners;
        } else {
            blsNonSignerThreshold = totalNodes / 3;
        }
    }

    /// @notice Contract begins locked and owner can start after nodes have been populated and hardfork has begun
    function start() public onlyOwner {
        IsActive = true;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setStakingRequirement(uint256 newRequirement) public onlyOwner {
        require(newRequirement > 0, "Staking requirement must be positive");
        stakingRequirement = newRequirement;
        emit StakingRequirementUpdated(newRequirement);
    }

    function setUpperLimitNonSigners(uint256 newRequirement) public onlyOwner {
        require(newRequirement > 0, "Staking requirement must be positive");
        upperLimitNonSigners = newRequirement;
        emit NonSignersLimitUpdated(newRequirement);
    }

}


