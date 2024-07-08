// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./interfaces/IServiceNodeRewards.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./libraries/Pairing.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Service Node Rewards Contract
/// @notice This contract manages the rewards and public keys for service nodes.
contract ServiceNodeRewards is Initializable, Ownable2StepUpgradeable, PausableUpgradeable, IServiceNodeRewards {
    using SafeERC20 for IERC20;

    bool public isStarted;

    IERC20 public designatedToken;
    IERC20 public foundationPool;

    uint64 public constant LIST_SENTINEL = 0;
    uint256 public constant MAX_SERVICE_NODE_REMOVAL_WAIT_TIME = 30 days;
    uint256 public constant MAX_PERMITTED_PUBKEY_AGGREGATIONS_LOWER_BOUND = 5;
    // A small contributor is one who contributes less than 1/DIVISOR of the total; such a
    // contributor may not initiate a leave request within the initial LEAVE_DELAY:
    uint256 public constant SMALL_CONTRIBUTOR_LEAVE_DELAY = 30 days;
    uint256 public constant SMALL_CONTRIBUTOR_DIVISOR = 4;

    uint64 public nextServiceNodeID;
    uint256 public totalNodes;
    uint256 public blsNonSignerThreshold;
    uint256 public blsNonSignerThresholdMax;
    uint256 public signatureExpiry;

    bytes32 public proofOfPossessionTag;
    bytes32 public rewardTag;
    bytes32 public removalTag;
    bytes32 public liquidateTag;
    bytes32 public hashToG2Tag;

    uint256 private _stakingRequirement;
    uint256 private _maxContributors;
    uint256 private _liquidatorRewardRatio;
    uint256 private _poolShareOfLiquidationRatio;
    uint256 private _recipientRatio;

    /// @notice Constructor for the Service Node Rewards Contract
    ///
    /// @param token_ The token used for rewards
    /// @param foundationPool_ The foundation pool for the token
    /// @param stakingRequirement_ The staking requirement for service nodes
    /// @param liquidatorRewardRatio_ The reward ratio for liquidators
    /// @param poolShareOfLiquidationRatio_ The pool share ratio during liquidation
    /// @param recipientRatio_ The recipient ratio for rewards
    function initialize(
        address token_,
        address foundationPool_,
        uint256 stakingRequirement_,
        uint256 maxContributors_,
        uint256 liquidatorRewardRatio_,
        uint256 poolShareOfLiquidationRatio_,
        uint256 recipientRatio_
    ) public initializer {
        if (recipientRatio_ < 1) revert RecipientRewardsTooLow();
        isStarted = false;
        totalNodes = 0;
        blsNonSignerThreshold = 0;
        blsNonSignerThresholdMax = 300;
        proofOfPossessionTag = buildTag("BLS_SIG_TRYANDINCREMENT_POP");
        rewardTag = buildTag("BLS_SIG_TRYANDINCREMENT_REWARD");
        removalTag = buildTag("BLS_SIG_TRYANDINCREMENT_REMOVE");
        liquidateTag = buildTag("BLS_SIG_TRYANDINCREMENT_LIQUIDATE");
        hashToG2Tag = buildTag("BLS_SIG_HASH_TO_FIELD_TAG");
        signatureExpiry = 10 minutes;

        designatedToken = IERC20(token_);
        foundationPool = IERC20(foundationPool_);
        _stakingRequirement = stakingRequirement_;
        _maxContributors = maxContributors_;
        _liquidatorRewardRatio = liquidatorRewardRatio_;
        _poolShareOfLiquidationRatio = poolShareOfLiquidationRatio_;
        _recipientRatio = recipientRatio_;
        nextServiceNodeID = LIST_SENTINEL + 1;

        // Doubly-linked list with sentinel that points to itself.
        //
        // +-<prev- [Sentinel] -next->-+
        // |                           |
        // +----------------------------

        _serviceNodes[LIST_SENTINEL].prev = LIST_SENTINEL;
        _serviceNodes[LIST_SENTINEL].next = LIST_SENTINEL;
        __Ownable_init(msg.sender);
    }

    mapping(uint64 => ServiceNode) private _serviceNodes;
    mapping(address => Recipient) public recipients;
    // Maps a bls public key (G1Point) to a serviceNodeID
    mapping(bytes blsPublicKey => uint64 serviceNodeID) public serviceNodeIDs;

    BN256G1.G1Point public _aggregatePubkey;
    uint256         public _lastHeightPubkeyWasAggregated;
    uint256         public _numPubkeyAggregationsForHeight;

    // MODIFIERS
    modifier whenStarted() {
        if (!isStarted) {
            revert ContractNotStarted();
        }
        _;
    }

    modifier hasEnoughSigners(uint256 numberOfNonSigningServiceNodes) {
        if (numberOfNonSigningServiceNodes > blsNonSignerThreshold) {
            uint256 numberOfServiceNodes = serviceNodesLength();
            revert InsufficientBLSSignatures(
                numberOfServiceNodes - numberOfNonSigningServiceNodes,
                numberOfServiceNodes - blsNonSignerThreshold
            );
        }
        _;
    }

    // EVENTS
    event NewSeededServiceNode(uint64 indexed serviceNodeID, BN256G1.G1Point pubkey);
    event NewServiceNode(
        uint64 indexed serviceNodeID,
        address recipient,
        BN256G1.G1Point pubkey,
        ServiceNodeParams serviceNode,
        Contributor[] contributors
    );
    event RewardsBalanceUpdated(address indexed recipientAddress, uint256 amount, uint256 previousBalance);
    event RewardsClaimed(address indexed recipientAddress, uint256 amount);
    event BLSNonSignerThresholdMaxUpdated(uint256 newMax);
    event ServiceNodeLiquidated(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event ServiceNodeRemoval(
        uint64 indexed serviceNodeID,
        address recipient,
        uint256 returnedAmount,
        BN256G1.G1Point pubkey
    );
    event ServiceNodeRemovalRequest(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event StakingRequirementUpdated(uint256 newRequirement);
    event SignatureExpiryUpdated(uint256 newExpiry);

    // ERRORS
    error DeleteSentinelNodeNotAllowed();
    error BLSPubkeyAlreadyExists(uint64 serviceNodeID);
    error BLSPubkeyDoesNotMatch(uint64 serviceNodeID, BN256G1.G1Point pubkey);
    error CallerNotContributor(uint64 serviceNodeID, address contributor);
    error ContractAlreadyStarted();
    error ContractNotStarted();
    error ContributionTotalMismatch(uint256 required, uint256 provided);
    error EarlierLeaveRequestMade(uint64 serviceNodeID, address recipient);
    error SmallContributorLeaveTooEarly(uint64 serviceNodeID, address recipient);
    error FirstContributorMismatch(address operator, address contributor);
    error InsufficientBLSSignatures(uint256 numSigners, uint256 requiredSigners);
    error InvalidBLSSignature();
    error InvalidBLSProofOfPossession();
    error LeaveRequestTooEarly(uint64 serviceNodeID, uint256 timestamp, uint256 currenttime);
    error MaxContributorsExceeded();
    error NullRecipient();
    error RecipientAddressDoesNotMatch(address expectedRecipient, address providedRecipient, uint256 serviceNodeID);
    error RecipientRewardsTooLow();
    error ServiceNodeDoesntExist(uint64 serviceNodeID);
    error SignatureExpired(uint64 serviceNodeID, uint256 timestamp, uint256 currenttime);

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// CLAIMING REWARDS
    /// This section contains all the functions necessary for a user to receive
    /// tokens from the service node network as follows. The user will:
    ///
    /// 1) Go to service node network and request they sign an amount that they
    ///    are allowed to claim. Each node will individually sign the user's
    ///    details into an aggregate signature.
    /// 2) Call `updateRewardsBalance` with their details and the produced
    ///    signature. This signature is verified and the user's rewards balance
    ///    is updated.
    /// 3) Call `claimRewards` which will pay out the unclaimed rewards to the
    ///    user.

    /// @notice Updates the rewards balance for a given recipient. Calling this
    /// requires a BLS signature from the network.
    ///
    /// @param recipientAddress Address of the recipient to update.
    /// @param recipientRewards Amount of rewards the recipient is allowed to
    /// claim.
    /// @param blsSignature 128 byte BLS proof of possession signature, signed
    /// over the tag, `recipientAddress` and `recipientRewards`.
    /// @param ids Array of service node IDs that didn't sign the signature
    /// and are to be excluded from verification.
    function updateRewardsBalance(
        address recipientAddress,
        uint256 recipientRewards,
        BLSSignatureParams calldata blsSignature,
        uint64[] memory ids
    ) external whenNotPaused whenStarted hasEnoughSigners(ids.length) {
        if (recipientAddress == address(0)) {
            revert NullRecipient();
        }

        if (recipients[recipientAddress].rewards >= recipientRewards) {
            revert RecipientRewardsTooLow();
        }

        // NOTE: Validate signature
        {
            bytes memory encodedMessage = abi.encodePacked(rewardTag, recipientAddress, recipientRewards);
            BN256G2.G2Point memory Hm = BN256G2.hashToG2(encodedMessage, hashToG2Tag);
            validateSignatureOrRevert(ids, blsSignature, Hm);
        }

        uint256 previousBalance = recipients[recipientAddress].rewards;
        recipients[recipientAddress].rewards = recipientRewards;
        emit RewardsBalanceUpdated(recipientAddress, recipientRewards, previousBalance);
    }

    /// @dev Internal function to handle reward claims. Will transfer the
    /// available rewards worth of our token to claimingAddress
    /// @param claimingAddress The address claiming the rewards.
    function _claimRewards(address claimingAddress) internal {
        uint256 claimedRewards = recipients[claimingAddress].claimed;
        uint256 totalRewards = recipients[claimingAddress].rewards;
        uint256 amountToRedeem = totalRewards - claimedRewards;

        recipients[claimingAddress].claimed = totalRewards;
        emit RewardsClaimed(claimingAddress, amountToRedeem);

        SafeERC20.safeTransfer(designatedToken, claimingAddress, amountToRedeem);
    }

    /// @notice Claim the rewards due for the active wallet invoking the claim.
    function claimRewards() public {
        _claimRewards(msg.sender);
    }

    /// MANAGING BLS PUBLIC KEY LIST
    /// This section contains all the functions necessary to add and remove
    /// service nodes from the service nodes linked list. The regular process
    /// for a new user is to call `addBLSPublicKey` with the details of their
    /// service node. The smart contract will do some verification over the bls
    /// key, take a staked amount of SENT tokens, and then add this node to
    /// its internal public key list. Keys that are in this list will be able to
    /// participate in BLS signing events going forward (such as allowing the
    /// withdrawal of funds and removal of other BLS keys)
    ///
    /// To leave the network and get the staked amount back the user should
    /// first initate the removal of their key by calling
    /// `initiateRemoveBLSPublicKey` this function simply notifys the network
    /// and begins a timer of 15 days which the user must wait before they can
    /// exit. Once the 15 days has passed the network will then provide a bls
    /// signature so the user can call `removeBLSPublicKeyWithSignature` which
    /// will remove their public key from the linked list. Once this occurs the
    /// network will then allow the user to claim their stake back via the
    /// `updateRewards` and `claimRewards` functions.

    /// @notice Adds a BLS public key to the list of service nodes. Requires
    /// a proof of possession BLS signature to prove user controls the public
    /// key being added.
    ///
    /// @param blsPubkey 64 byte BLS public key for the service node.
    /// @param blsSignature 128 byte BLS proof of possession signature that
    /// proves ownership of the `blsPubkey`.
    /// @param serviceNodeParams The service node to add including the x25519
    /// public key and signature that proves ownership of the private component
    /// of the public key and the desired fee the operator is charging.
    /// @param contributors An optional list of contributors for
    /// multi-contribution service nodes. The first contributor's information
    /// must be set to the operator (the current interacting wallet).
    ///
    /// If this list of empty, it is assumed that the service node is ran in
    /// a solo configuration under the current interacting wallet.
    function addBLSPublicKey(
        BN256G1.G1Point calldata blsPubkey,
        BLSSignatureParams calldata blsSignature,
        ServiceNodeParams calldata serviceNodeParams,
        Contributor[] calldata contributors
    ) external whenNotPaused {
        _addBLSPublicKey(blsPubkey, blsSignature, msg.sender, serviceNodeParams, contributors);
    }

    /// @dev Internal function to add a BLS public key.
    ///
    /// @param blsPubkey 64 byte BLS public key for the service node.
    /// @param blsSignature 128 byte BLS proof of possession signature that
    /// proves ownership of the `blsPubkey`.
    /// @param caller The address calling this function
    /// @param serviceNodeParams Service node public key, signature proving
    /// ownership of public key and fee that operator is charging
    /// @param contributors An optional list of contributors to the service
    /// node, first is always the operator.
    function _addBLSPublicKey(
        BN256G1.G1Point calldata blsPubkey,
        BLSSignatureParams calldata blsSignature,
        address caller,
        ServiceNodeParams calldata serviceNodeParams,
        Contributor[] memory contributors
    ) internal whenStarted {
        if (contributors.length > maxContributors()) revert MaxContributorsExceeded();
        if (contributors.length > 0) {
            uint256 totalAmount = 0;
            for (uint256 i = 0; i < contributors.length; i++) {
                totalAmount += contributors[i].stakedAmount;
            }
            if (totalAmount != _stakingRequirement) revert ContributionTotalMismatch(_stakingRequirement, totalAmount);
        } else {
            contributors = new Contributor[](1);
            contributors[0] = Contributor(caller, _stakingRequirement);
        }
        uint64 serviceNodeID = serviceNodeIDs[BN256G1.getKeyForG1Point(blsPubkey)];
        if (serviceNodeID != 0) revert BLSPubkeyAlreadyExists(serviceNodeID);
        validateProofOfPossession(blsPubkey, blsSignature, caller, serviceNodeParams.serviceNodePubkey);

        uint64 allocID = serviceNodeAdd(blsPubkey);
        _serviceNodes[allocID].operator = contributors[0].addr;
        for (uint256 i = 0; i < contributors.length; i++) {
            _serviceNodes[allocID].contributors.push(contributors[i]);
        }
        _serviceNodes[allocID].deposit = _stakingRequirement;

        updateBLSNonSignerThreshold();
        emit NewServiceNode(allocID, caller, blsPubkey, serviceNodeParams, contributors);
        SafeERC20.safeTransferFrom(designatedToken, caller, address(this), _stakingRequirement);
    }

    /// @notice Validates the proof of possession for a given BLS public key.
    /// @param blsPubkey 64 byte BLS public key for the service node.
    /// @param blsSignature 128 byte BLS proof of possession signature that
    /// proves ownership of the `blsPubkey`.
    /// @param caller The address calling the `addBLSPublicKey` function
    /// @param serviceNodePubkey Service node's 32 byte public key.
    function validateProofOfPossession(
        BN256G1.G1Point memory blsPubkey,
        BLSSignatureParams calldata blsSignature,
        address caller,
        uint256 serviceNodePubkey
    ) internal {
        bytes memory encodedMessage = abi.encodePacked(
            proofOfPossessionTag,
            blsPubkey.X,
            blsPubkey.Y,
            caller,
            serviceNodePubkey
        );
        BN256G2.G2Point memory Hm = BN256G2.hashToG2(encodedMessage, hashToG2Tag);

        BN256G2.G2Point memory signature = BN256G2.G2Point(
            [blsSignature.sigs1, blsSignature.sigs0],
            [blsSignature.sigs3, blsSignature.sigs2]
        );
        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(blsPubkey), Hm)) {
            revert InvalidBLSProofOfPossession();
        }
    }

    /// @notice Initiates a request for the service node to leave the network by
    /// their service node ID.
    ///
    /// @dev This simply notifies the network that the node wishes to leave
    /// the network. There will be a delay before the network allows this node
    /// to exit gracefully. Should be called first and later once the network
    /// is happy for node to exit the user should call
    /// `removeBLSPublicKeyWithSignature` with a valid aggregate BLS signature
    /// returned by the network.
    ///
    /// @param serviceNodeID The ID of the service node to be removed.
    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) public whenNotPaused {
        _initiateRemoveBLSPublicKey(serviceNodeID, msg.sender);
    }

    /// @param serviceNodeID The ID of the service node to be removed.
    /// @param caller The address of a contributor associated with the service
    /// node that is initiating the removal.
    function _initiateRemoveBLSPublicKey(uint64 serviceNodeID, address caller) internal whenStarted {
        bool isContributor = false;
        bool isSmall = false; // "small" means less than 25% of the SN total stake
        for (uint256 i = 0; i < _serviceNodes[serviceNodeID].contributors.length; i++) {
            if (_serviceNodes[serviceNodeID].contributors[i].addr == caller) {
                isContributor = true;
                isSmall =
                    SMALL_CONTRIBUTOR_DIVISOR * _serviceNodes[serviceNodeID].contributors[i].stakedAmount
                        < _serviceNodes[serviceNodeID].deposit;
                break;
            }
        }
        if (!isContributor) revert CallerNotContributor(serviceNodeID, caller);

        if (_serviceNodes[serviceNodeID].leaveRequestTimestamp != 0)
            revert EarlierLeaveRequestMade(serviceNodeID, caller);
        if (isSmall && block.timestamp < _serviceNodes[serviceNodeID].addedTimestamp + SMALL_CONTRIBUTOR_LEAVE_DELAY)
            revert SmallContributorLeaveTooEarly(serviceNodeID, caller);
        _serviceNodes[serviceNodeID].leaveRequestTimestamp = block.timestamp;
        emit ServiceNodeRemovalRequest(serviceNodeID, caller, _serviceNodes[serviceNodeID].pubkey);
    }

    /// @notice Removes a BLS public key using an aggregated BLS signature from
    /// the network.
    ///
    /// @dev This is the usual path for a node to exit the network.
    /// Anyone can call this function but only the user being removed will
    /// benefit from calling this. Once removed from the smart contracts list
    /// the network will release the staked amount.
    ///
    /// @param blsPubkey 64 byte BLS public key for the service node to be
    /// removed.
    /// @param timestamp The signature creation time.
    /// @param blsSignature 128 byte BLS signature that affirms that the
    /// `blsPubkey` is to be removed.
    /// @param ids Array of service node IDs that didn't sign the signature
    /// and are to be excluded from verification.
    function removeBLSPublicKeyWithSignature(
        BN256G1.G1Point calldata blsPubkey,
        uint256 timestamp,
        BLSSignatureParams calldata blsSignature,
        uint64[] memory ids
    ) external whenNotPaused whenStarted hasEnoughSigners(ids.length) {
        bytes memory pubkeyBytes = BN256G1.getKeyForG1Point(blsPubkey);
        uint64 serviceNodeID = serviceNodeIDs[pubkeyBytes];
        if (signatureTimestampHasExpired(timestamp)) {
            revert SignatureExpired(serviceNodeID, timestamp, block.timestamp);
        }

        if (
            blsPubkey.X != _serviceNodes[serviceNodeID].pubkey.X || blsPubkey.Y != _serviceNodes[serviceNodeID].pubkey.Y
        ) revert BLSPubkeyDoesNotMatch(serviceNodeID, blsPubkey);

        // NOTE: Validate signature
        {
            bytes memory encodedMessage = abi.encodePacked(removalTag, blsPubkey.X, blsPubkey.Y, timestamp);
            BN256G2.G2Point memory Hm = BN256G2.hashToG2(encodedMessage, hashToG2Tag);
            validateSignatureOrRevert(ids, blsSignature, Hm);
        }

        _removeBLSPublicKey(serviceNodeID, _serviceNodes[serviceNodeID].deposit);
    }

    /// @notice Removes a BLS public key after the required wait time on leave
    /// request has transpired.
    ///
    /// @dev This can be called without a signature because the node has
    /// waited the duration permitted to exit the network without a signature.
    ///
    /// @param serviceNodeID The ID of the service node to be removed..
    function removeBLSPublicKeyAfterWaitTime(uint64 serviceNodeID) external whenNotPaused whenStarted {
        uint256 leaveRequestTimestamp = _serviceNodes[serviceNodeID].leaveRequestTimestamp;
        if (leaveRequestTimestamp == 0) {
            revert LeaveRequestTooEarly(serviceNodeID, leaveRequestTimestamp, block.timestamp);
        }

        uint256 timestamp = leaveRequestTimestamp + MAX_SERVICE_NODE_REMOVAL_WAIT_TIME;
        if (block.timestamp <= timestamp) {
            revert LeaveRequestTooEarly(serviceNodeID, timestamp, block.timestamp);
        }

        _removeBLSPublicKey(serviceNodeID, _serviceNodes[serviceNodeID].deposit);
    }

    /// @dev Internal function to remove a service node from the contract. This
    /// function updates the linked-list and mapping information for the specified
    /// `serivceNodeID`.
    ///
    /// @param serviceNodeID The ID of the service node to be removed.
    function _removeBLSPublicKey(uint64 serviceNodeID, uint256 returnedAmount) internal {
        address operator = _serviceNodes[serviceNodeID].operator;
        BN256G1.G1Point memory pubkey = _serviceNodes[serviceNodeID].pubkey;
        serviceNodeDelete(serviceNodeID);

        updateBLSNonSignerThreshold();
        emit ServiceNodeRemoval(serviceNodeID, operator, returnedAmount, pubkey);
    }

    /// @notice Removes a service node by liquidating their node from the
    /// network rewarding the caller for maintaining the list.
    ///
    /// This function can be called by anyone, but requires the network to
    /// approve the liquidation by aggregating a valid BLS signature. The nodes
    /// will only provide this signature if the consensus rules permit the node
    /// to be forcibly removed (e.g. the node was deregistered by consensus in
    /// Oxen's state-chain).
    ///
    /// @param blsPubkey 64 byte BLS public key for the service node to be
    /// removed.
    /// @param timestamp The signature creation time.
    /// @param blsSignature 128 byte BLS signature that affirms that the
    /// `blsPubkey` is to be liquidated.
    /// @param ids Array of service node IDs that didn't sign the signature
    /// and are to be excluded from verification.
    function liquidateBLSPublicKeyWithSignature(
        BN256G1.G1Point calldata blsPubkey,
        uint256 timestamp,
        BLSSignatureParams calldata blsSignature,
        uint64[] memory ids
    ) external whenNotPaused whenStarted hasEnoughSigners(ids.length) {
        bytes memory pubkeyBytes = BN256G1.getKeyForG1Point(blsPubkey);
        uint64 serviceNodeID = serviceNodeIDs[pubkeyBytes];
        if (signatureTimestampHasExpired(timestamp)) {
            revert SignatureExpired(serviceNodeID, timestamp, block.timestamp);
        }

        ServiceNode memory node = _serviceNodes[serviceNodeID];
        if (blsPubkey.X != node.pubkey.X || blsPubkey.Y != node.pubkey.Y) {
            revert BLSPubkeyDoesNotMatch(serviceNodeID, blsPubkey);
        }

        // NOTE: Validate signature
        {
            bytes memory encodedMessage = abi.encodePacked(liquidateTag, blsPubkey.X, blsPubkey.Y, timestamp);
            BN256G2.G2Point memory Hm = BN256G2.hashToG2(encodedMessage, hashToG2Tag);
            validateSignatureOrRevert(ids, blsSignature, Hm);
        }

        // Calculating how much liquidator is paid out
        emit ServiceNodeLiquidated(serviceNodeID, node.operator, node.pubkey);
        uint256 ratioSum = _poolShareOfLiquidationRatio + _liquidatorRewardRatio + _recipientRatio;
        uint256 deposit = node.deposit;
        uint256 liquidatorAmount = (deposit * _liquidatorRewardRatio) / ratioSum;
        uint256 poolAmount = deposit * _poolShareOfLiquidationRatio == 0
            ? 0
            : (_poolShareOfLiquidationRatio - 1) / ratioSum + 1;

        _removeBLSPublicKey(serviceNodeID, deposit - liquidatorAmount - poolAmount);

        // Transfer funds to pool and liquidator
        if (_liquidatorRewardRatio > 0) SafeERC20.safeTransfer(designatedToken, msg.sender, liquidatorAmount);
        if (_poolShareOfLiquidationRatio > 0)
            SafeERC20.safeTransfer(designatedToken, address(foundationPool), poolAmount);
    }

    /// @notice Seeds the public key list with an initial set of service nodes.
    ///
    /// This function can only be called after deployment of the contract by the
    /// owner, and, prior to starting the contract.
    ///
    /// @dev This should be called before the hardfork by the foundation to
    /// ensure the public key list is ready to operate. The foundation will
    /// enumerate the keys from Session Nodes in C++ via cryptographic proofs
    /// which include a proof-of-possession to verify that the
    /// Session Node has the secret-component of the BLS public key they are
    /// declaring.
    ///
    /// Depending on the number of nodes that must be seeded, this function
    /// may necessarily be called multiple times due to gas limits.
    ///
    /// @param nodes Array of service nodes to seed the smart contract with
    function seedPublicKeyList(SeedServiceNode[] calldata nodes) external onlyOwner {
        require(!isStarted, "The rewards list can only be seeded after "
                "deployment and before `start` is invoked on the contract.");

        for (uint256 i = 0; i < nodes.length; i++) {
            SeedServiceNode calldata node = nodes[i];

            // NOTE: Basic sanity checks
            require(node.deposit > 0, "Deposit must be non-zero");
            require(node.pubkey.X != 0 && node.pubkey.Y != 0, "The zero public key is not permitted");
            require(node.contributors.length > 0,
                    "There must be at-least one contributor in the node. The first contributor is defined to be the operator.");
            require(node.contributors.length <= 10,
                    "Seeded service cannot have more than 10 contributors");

            // NOTE: Add node to the smart contract
            uint64 allocID                  = serviceNodeAdd(node.pubkey);
            _serviceNodes[allocID].deposit  = node.deposit;
            _serviceNodes[allocID].operator = node.contributors[0].addr;

            uint256 stakedAmountSum = 0;
            for (uint256 contributorIndex = 0; contributorIndex < node.contributors.length; contributorIndex++) {
                Contributor calldata contributor  = node.contributors[contributorIndex];
                stakedAmountSum                  += contributor.stakedAmount;
                require(contributor.addr         != address(0), "Contributor address cannot be the nil address (zero)");
                _serviceNodes[allocID].contributors.push(contributor);
            }
            require(stakedAmountSum == node.deposit,
                    "Sum of the contributor(s) staked amounts do not match the deposit of the node");

            emit NewSeededServiceNode(allocID, node.pubkey);
        }

        updateBLSNonSignerThreshold();
    }

    /// @notice Add the service node with the specified BLS public key to
    /// the service node list. EVM revert if the service node already exists.
    ///
    /// @return result The ID allocated for the service node. The service node
    /// can then be accessed by `_serviceNodes[result]`
    function serviceNodeAdd(BN256G1.G1Point memory pubkey) internal returns (uint64 result) {
        // NOTE: Check if the service node already exists
        // (e.g. <BLS Key> -> <SN> mapping)
        bytes memory pubkeyBytes = BN256G1.getKeyForG1Point(pubkey);
        if (serviceNodeIDs[pubkeyBytes] != LIST_SENTINEL) revert BLSPubkeyAlreadyExists(serviceNodeIDs[pubkeyBytes]);

        // NOTE: After the contract has started (e.g. the contract has been
        // seeded) we limit the number of public keys permitted to be aggregated
        // within a single block.
        if (isStarted) {
            if (_lastHeightPubkeyWasAggregated < block.number) {
                _lastHeightPubkeyWasAggregated  = block.number;
                _numPubkeyAggregationsForHeight = 0;
            }
            _numPubkeyAggregationsForHeight++;

            uint256 limit = maxPermittedPubkeyAggregations();
            require(_numPubkeyAggregationsForHeight <= limit,
                    "The maximum number of new Session Nodes permitted per block has been "
                    "exceeded. Session Node can not be added, please retry again in the next "
                    "block.");
        }

        result = nextServiceNodeID;
        nextServiceNodeID += 1;
        totalNodes += 1;

        // NOTE: Create service node slot and patch up the slot links.
        //
        // The following is the insertion pattern in a doubly-linked list
        // with sentinel at index 0
        //
        // ```c
        // node->next       = sentinel;
        // node->prev       = sentinel->prev;
        // node->next->prev = node;
        // node->prev->next = node;
        // ```
        _serviceNodes[result].next = LIST_SENTINEL;
        _serviceNodes[result].prev = _serviceNodes[LIST_SENTINEL].prev;
        _serviceNodes[_serviceNodes[result].next].prev = result;
        _serviceNodes[_serviceNodes[result].prev].next = result;

        // NOTE: Assign BLS pubkey
        _serviceNodes[result].pubkey = pubkey;

        _serviceNodes[result].addedTimestamp = block.timestamp;

        // NOTE: Create mapping from <BLS Key> -> <SN Linked List Index>
        serviceNodeIDs[pubkeyBytes] = result;

        if (totalNodes == 1) {
            _aggregatePubkey = pubkey;
        } else {
            _aggregatePubkey = BN256G1.add(_aggregatePubkey, pubkey);
        }

        return result;
    }

    /// @notice Delete the service node with `nodeID`
    /// @param nodeID The ID of the service node to delete
    function serviceNodeDelete(uint64 nodeID) internal {
        require(totalNodes > 0);
        if (nodeID == LIST_SENTINEL) revert DeleteSentinelNodeNotAllowed();

        ServiceNode memory node = _serviceNodes[nodeID];

        // The following is the deletion pattern in a doubly-linked list
        // with sentinel at index 0
        //
        // ```c
        // node->next->prev = node->prev;
        // node->prev->next = node->next;
        // ```
        _serviceNodes[node.next].prev = node.prev;
        _serviceNodes[node.prev].next = node.next;

        // NOTE: Update aggregate BLS key
        _aggregatePubkey = BN256G1.add(_aggregatePubkey, BN256G1.negate(node.pubkey));

        // NOTE: Delete service node from EVM storage
        bytes memory pubkeyBytes = BN256G1.getKeyForG1Point(node.pubkey);
        delete _serviceNodes[nodeID];
        delete serviceNodeIDs[pubkeyBytes]; // Delete mapping

        totalNodes -= 1;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                        Governance                        //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice allows anyone to update the service nodes length variable
    function updateServiceNodesLength() public {
        totalNodes = serviceNodesLength();
    }

    /// @notice Updates the internal threshold for how many non signers an
    /// aggregate signature can contain before being invalid
    function updateBLSNonSignerThreshold() internal {
        uint256 oneThirdOfNodes = totalNodes / 3;
        blsNonSignerThreshold = oneThirdOfNodes > blsNonSignerThresholdMax ? blsNonSignerThresholdMax : oneThirdOfNodes;
    }

    /// @notice Contract begins locked and owner can start after nodes have been
    /// populated and hardfork has begun
    function start() public onlyOwner {
        isStarted = true;
    }

    /// @notice Pause will prevent new keys from being added and removed, and
    /// also the claiming of rewards
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpause will allow all functions to work as usual
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Setter function for staking requirement, only callable by owner
    /// @param newRequirement the value being changed to
    function setStakingRequirement(uint256 newRequirement) public onlyOwner {
        require(newRequirement > 0, "Staking requirement must be positive");
        _stakingRequirement = newRequirement;
        emit StakingRequirementUpdated(newRequirement);
    }

    /// @notice Setter function for signature expiry, only callable by owner
    /// @param newExpiry the value being changed to
    function setSignatureExpiry(uint256 newExpiry) public onlyOwner {
        require(newExpiry > 0, "signature expiry must be positive");
        signatureExpiry = newExpiry;
        emit SignatureExpiryUpdated(newExpiry);
    }

    /// @notice Max number of permitted non-signers during signature aggregation
    /// applied when one third of the nodes exceeds this value. Only callable by
    /// the owner.
    /// @param newMax The new maximum non-signer threshold
    function setBLSNonSignerThresholdMax(uint256 newMax) public onlyOwner {
        require(newMax > 0, "The new BLS non-signer threshold must be non-zero");
        blsNonSignerThresholdMax = newMax;
        emit BLSNonSignerThresholdMaxUpdated(newMax);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Validate the signature against `hashToVerify` by negating the
    /// list of non-signers from the aggregate BLS public key stored on the
    /// smart contract.
    ///
    /// This function reverts if the signature can not be verified against
    /// `hashToVerify`.
    function validateSignatureOrRevert(
        uint64[] memory listOfNonSigners,
        BLSSignatureParams memory blsSignature,
        BN256G2.G2Point memory hashToVerify
    ) private {
        BN256G1.G1Point memory pubkey;
        uint256 listOfNonSignersLength = listOfNonSigners.length;
        for (uint256 i = 0; i < listOfNonSignersLength; i++) {
            uint64 serviceNodeID = listOfNonSigners[i];
            pubkey = BN256G1.add(pubkey, _serviceNodes[serviceNodeID].pubkey);
        }

        pubkey = BN256G1.add(_aggregatePubkey, BN256G1.negate(pubkey));
        BN256G2.G2Point memory signature = BN256G2.G2Point(
            [blsSignature.sigs1, blsSignature.sigs0],
            [blsSignature.sigs3, blsSignature.sigs2]
        );

        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), hashToVerify)) {
            revert InvalidBLSSignature();
        }
    }

    /// @notice Verify that time-since the timestamp has not exceeded the expiry
    /// threshold `signatureExpiry`.
    /// @return result True if the timestamp has expired, false otherwise.
    function signatureTimestampHasExpired(uint256 timestamp) private view returns (bool result) {
        result = block.timestamp > timestamp + signatureExpiry;
        return result;
    }

    /// @notice Counts the number of service nodes in the linked list.
    /// @return count The total number of service nodes in the list.
    function serviceNodesLength() public view returns (uint256 count) {
        uint64 currentNode = _serviceNodes[LIST_SENTINEL].next;
        count = 0;

        while (currentNode != LIST_SENTINEL) {
            count++;
            currentNode = _serviceNodes[currentNode].next;
        }

        return count;
    }

    /// @notice The maximum number of pubkey aggregations permitted for the
    /// current block height.
    ///
    /// @dev This is currently defined as max(5, 2 percent of the network).
    ///
    /// This value is used in tandem with `_numPubkeyAggregationsForHeight`
    /// which tracks the current number of aggregations thus far for the current
    /// block in the blockchain. This counter gets reset to 0 for each new
    /// block.
    function maxPermittedPubkeyAggregations() public view returns (uint256 result) {
        uint256 twoPercentOfTotalNodes = totalNodes * 2 / 100;
        result = twoPercentOfTotalNodes > MAX_PERMITTED_PUBKEY_AGGREGATIONS_LOWER_BOUND
                                        ? twoPercentOfTotalNodes
                                        : MAX_PERMITTED_PUBKEY_AGGREGATIONS_LOWER_BOUND;
    }

    /// @notice Getter for a single service node given their service node ID
    /// @param serviceNodeID the unique identifier of the service node
    /// @return Service Node Struct from the linked list of all nodes
    function serviceNodes(uint64 serviceNodeID) external view returns (ServiceNode memory) {
        return _serviceNodes[serviceNodeID];
    }

    /// @notice Getter function for liquidatorRewardRatio
    function liquidatorRewardRatio() external view returns (uint256) {
        return _liquidatorRewardRatio;
    }

    /// @notice Getter function for poolShareofLiquidationRatio
    function poolShareOfLiquidationRatio() external view returns (uint256) {
        return _poolShareOfLiquidationRatio;
    }

    /// @notice Getter function for recipientRatio
    function recipientRatio() external view returns (uint256) {
        return _recipientRatio;
    }

    /// @notice Getter function for stakingRequirement
    function stakingRequirement() external view returns (uint256) {
        return _stakingRequirement;
    }

    /// @notice Getter function for maxContributors
    /// @dev If this is changed the size of contributors in IServiceNodeRewards needs to also be changed.
    function maxContributors() public view returns (uint256) {
        return _maxContributors;
    }

    /// @notice Getter function for the aggregatePubkey
    function aggregatePubkey() external view returns (BN256G1.G1Point memory) {
        return _aggregatePubkey;
    }

    /// @dev Builds a tag string using a base tag and contract-specific
    /// information. This is used when signing messages to prevent reuse of
    /// signatures across different domains (chains/functions/contracts)
    ///
    /// @param baseTag The base string for the tag.
    /// @return The constructed tag string.
    function buildTag(string memory baseTag) private view returns (bytes32) {
        return keccak256(bytes(abi.encodePacked(baseTag, block.chainid, address(this))));
    }
}
