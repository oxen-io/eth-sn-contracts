// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./Pairing.sol";

import "hardhat/console.sol";

contract ServiceNodeRewards is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable designatedToken;
    IERC20 public immutable foundationPool;

    uint64 public nextServiceNodeID;
    uint64 public constant LIST_END = type(uint64).max;
    uint256 public constant MAX_SERVICE_NODE_REMOVAL_WAIT_TIME = 30 days;

    /*string immutable proofOfPossessionTag = "BLS_SIG_TRYANDINCREMENT_POP" + block.chainid + address(this);*/
    string public proofOfPossessionTag;
    /*string immutable rewardTag = "BLS_SIG_TRYANDINCREMENT_REWARD" + block.chainid + address(this);*/
    string public rewardTag;
    /*string immutable removalTag = "BLS_SIG_TRYANDINCREMENT_REMOVE" + block.chainid + address(this);*/
    string public removalTag;
    /*string immutable liquidateTag = "BLS_SIG_TRYANDINCREMENT_LIQUIDATE" + block.chainid + address(this);*/
    string public liquidateTag;

    uint256 stakingRequirement;
    uint256 liquidatorRewardRatio;
    uint256 poolShareOfLiquidationRatio;
    uint256 recipientRatio;

    constructor(address _token, address _foundationPool, uint256 _stakingRequirement, uint256 _liquidatorRewardRatio, uint256 _poolShareOfLiquidationRatio, uint256 _recipientRatio) Ownable(msg.sender) {
        proofOfPossessionTag = buildTag("BLS_SIG_TRYANDINCREMENT_POP");
        rewardTag = buildTag("BLS_SIG_TRYANDINCREMENT_REWARD");
        removalTag = buildTag("BLS_SIG_TRYANDINCREMENT_REMOVE");
        liquidateTag = buildTag("BLS_SIG_TRYANDINCREMENT_LIQUIDATE");

        designatedToken = IERC20(_token);
        foundationPool = IERC20(_foundationPool);
        stakingRequirement = _stakingRequirement;

        poolShareOfLiquidationRatio = _poolShareOfLiquidationRatio;
        liquidatorRewardRatio = _liquidatorRewardRatio;
        recipientRatio = _recipientRatio;

        serviceNodes[LIST_END].previous = LIST_END;
        serviceNodes[LIST_END].next = LIST_END;
    }

    function buildTag(string memory baseTag) private view returns (string memory) {
        return string(abi.encodePacked(baseTag, Strings.toString(block.chainid), address(this)));
    }

    struct ServiceNode {
        uint64 next;
        uint64 previous;
        address recipient;
        BN256G1.G1Point pubkey;
        uint256 leaveRequestTimestamp;
        uint256 deposit;
    }

    struct Recipient {
        uint256 rewards;
        uint256 claimed;
    }

    mapping(uint64 => ServiceNode) public serviceNodes;
    mapping(address => Recipient) public recipients;
    mapping(bytes32 => uint64) public serviceNodeIDs;

    BN256G1.G1Point _aggregate_pubkey;

    // EVENTS
    event NewSeededServiceNode(uint64 indexed serviceNodeID, BN256G1.G1Point pubkey);
    event NewServiceNode(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event RewardsBalanceUpdated(address indexed recipientAddress, uint256 amount, uint256 previousBalance);
    event RewardsClaimed(address indexed recipientAddress, uint256 amount);
    event ServiceNodeLiquidated(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event ServiceNodeRemoval(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event ServiceNodeRemovalRequest(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);

    // ERRORS
    error RecipientAddressDoesNotMatch(address expectedRecipient, address providedRecipient, uint256 serviceNodeID);
    error BLSPubkeyAlreadyExists(uint64 serviceNodeID);
    error RecipientAddressNotProvided(uint64 serviceNodeID);
    error EarlierLeaveRequestMade(uint64 serviceNodeID, address recipient);
    error LeaveRequestTooEarly(uint64 serviceNodeID, uint256 timestamp);
    error ServiceNodeDoesntExist(uint64 serviceNodeID);
    error InvalidBLSSignature();
    error InvalidBLSProofOfPossession();
    error ArrayLengthMismatch();

    // CLAIMING REWARDS

    // TODO define encoding/decoding structure of message
    function updateRewardsBalance(uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint256 message, uint64[] memory ids) public {
        BN256G1.G1Point memory pubkey;
        for(uint256 i = 0; i < ids.length; i++) {
            pubkey = BN256G1.add(pubkey, serviceNodes[ids[i]].pubkey);
        }
        pubkey = BN256G1.add(_aggregate_pubkey, BN256G1.negate(pubkey));
        BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
        BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(rewardTag, message))));
        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSSignature();


        // TODO parse these from message
        address recipientAddress;
        uint256 recipientAmount;

        uint256 previousBalance = recipients[recipientAddress].rewards;
        recipients[recipientAddress].rewards = recipientAmount;
        emit RewardsBalanceUpdated(recipientAddress, recipientAmount, previousBalance);
    }

    function buildRecipientMessage(address recipientAddress, uint256 balance) public pure returns (bytes memory) {
        return abi.encode(recipientAddress, balance);
    }

    function _claimRewards(address claimingAddress) internal {
        uint256 claimedRewards = recipients[claimingAddress].claimed;
        uint256 totalRewards = recipients[claimingAddress].rewards;
        uint256 amountToRedeem = totalRewards - claimedRewards;
        recipients[claimingAddress].claimed = totalRewards;
        SafeERC20.safeTransfer(designatedToken, claimingAddress, amountToRedeem);
        emit RewardsClaimed(claimingAddress, amountToRedeem);
    }

    function claimRewards() public {
        _claimRewards(msg.sender);
    }

    // MANAGING BLS PUBLIC KEY LIST

    // Add Public Key Function
    function addBLSPublicKey(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3) public {
        _addBLSPublicKey(pkX, pkY, sigs0, sigs1, sigs2, sigs3, msg.sender);
    }

    function _addBLSPublicKey(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, address recipient) internal {
        BN256G1.G1Point memory pubkey = BN256G1.G1Point(pkX, pkY);
        uint64 serviceNodeID = serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)];
        if(serviceNodeID != 0) revert BLSPubkeyAlreadyExists(serviceNodeID);
        validateProofOfPossession(pubkey, sigs0, sigs1, sigs2, sigs3);
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
            _aggregate_pubkey = BN256G1.add(_aggregate_pubkey, pubkey);
        } else {
            _aggregate_pubkey = pubkey;
        }
        // TODO we also need service node public key
        emit NewServiceNode(nextServiceNodeID, recipient, pubkey);
        nextServiceNodeID++;
        SafeERC20.safeTransferFrom(designatedToken, recipient, address(this), stakingRequirement);
    }

    // Proof of possession tag: "BLS_SIG_TRYANDINCREMENT_POP" || block.chainid ||  address(this) || PUBKEY
    function validateProofOfPossession(BN256G1.G1Point memory pubkey, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3) internal {
        BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(proofOfPossessionTag, pubkey.X, pubkey.Y))));
        BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSProofOfPossession();

    }

    // Initiate Remove Public Key
    // Checking proof of possession again
    function _initiateRemoveBLSPublicKey(uint64 serviceNodeID, address recipient) internal {
        address serviceNodeRecipient = serviceNodes[serviceNodeID].recipient;
        if(serviceNodeRecipient == address(0)) revert RecipientAddressNotProvided(serviceNodeID);
        if(serviceNodeRecipient != recipient) revert RecipientAddressDoesNotMatch(serviceNodeRecipient, recipient, serviceNodeID);
        if(serviceNodes[serviceNodeID].leaveRequestTimestamp != 0) revert EarlierLeaveRequestMade(serviceNodeID, recipient);
        serviceNodes[serviceNodeID].leaveRequestTimestamp = block.timestamp;
        emit ServiceNodeRemovalRequest(serviceNodeID, recipient, serviceNodes[serviceNodeID].pubkey);
    }

    // Remove Public Key
    // Validating Signature from network
    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] memory ids) external {
        //Validating signature
        BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(removalTag, serviceNodeID))));
        BN256G1.G1Point memory pubkey;
        for(uint256 i = 0; i < ids.length; i++) {
            pubkey = BN256G1.add(pubkey, serviceNodes[ids[i]].pubkey);
        }
        pubkey = BN256G1.add(_aggregate_pubkey, BN256G1.negate(pubkey));
        BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSSignature();

        _removeBLSPublicKey(serviceNodeID);
    }

    function removeBLSPublicKeyAfterWaitTime(uint64 serviceNodeID) external {
        uint256 timestamp = serviceNodes[serviceNodeID].leaveRequestTimestamp + MAX_SERVICE_NODE_REMOVAL_WAIT_TIME;
        if(block.timestamp < timestamp) revert LeaveRequestTooEarly(serviceNodeID, timestamp);
        _removeBLSPublicKey(serviceNodeID);
    }

    function _removeBLSPublicKey(uint64 serviceNodeID) internal {
        uint64 previousServiceNode = serviceNodes[serviceNodeID].previous;
        uint64 nextServiceNode = serviceNodes[serviceNodeID].next;
        if (nextServiceNode == 0) revert ServiceNodeDoesntExist(serviceNodeID);

        serviceNodes[previousServiceNode].next = nextServiceNode;
        serviceNodes[nextServiceNode].previous = previousServiceNode;

        BN256G1.G1Point memory pubkey = BN256G1.G1Point(serviceNodes[serviceNodeID].pubkey.X, serviceNodes[serviceNodeID].pubkey.Y);

        _aggregate_pubkey = BN256G1.add(_aggregate_pubkey, BN256G1.negate(pubkey));

        delete serviceNodes[serviceNodeID].previous;
        delete serviceNodes[serviceNodeID].recipient;
        delete serviceNodes[serviceNodeID].next;
        delete serviceNodes[serviceNodeID].pubkey.X;
        delete serviceNodes[serviceNodeID].pubkey.Y;

        delete serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)];

        emit ServiceNodeRemoval(serviceNodeID, serviceNodes[serviceNodeID].recipient, serviceNodes[serviceNodeID].pubkey);
    }

    // Liquidate Public Key
    function liquidateBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] memory ids) external {
        //Validating signature
        BN256G2.G2Point memory Hm = BN256G2.hashToG2(BN256G2.hashToField(string(abi.encodePacked(liquidateTag, serviceNodeID))));
        BN256G1.G1Point memory pubkey;
        for(uint256 i = 0; i < ids.length; i++) {
            pubkey = BN256G1.add(pubkey, serviceNodes[ids[i]].pubkey);
        }
        pubkey = BN256G1.add(_aggregate_pubkey, BN256G1.negate(pubkey));
        BN256G2.G2Point memory signature = BN256G2.G2Point([sigs1,sigs0],[sigs3,sigs2]);
        if (!Pairing.pairing2(BN256G1.P1(), signature, BN256G1.negate(pubkey), Hm)) revert InvalidBLSSignature();


        _removeBLSPublicKey(serviceNodeID);

        // Calculating how much liquidator is paid out
        uint256 ratioSum = poolShareOfLiquidationRatio + liquidatorRewardRatio + recipientRatio;
        uint256 deposit = serviceNodes[serviceNodeID].deposit;

        if (liquidatorRewardRatio > 0)
            SafeERC20.safeTransfer(designatedToken, msg.sender, deposit * liquidatorRewardRatio/ratioSum);
        if (poolShareOfLiquidationRatio > 0)
            SafeERC20.safeTransfer(designatedToken, address(foundationPool), deposit * poolShareOfLiquidationRatio/ratioSum);
        emit ServiceNodeLiquidated(serviceNodeID, serviceNodes[serviceNodeID].recipient, serviceNodes[serviceNodeID].pubkey);
    }


    // seedPublicKeyList:
    /*An owner guarded function to set up the initial public key list. Before the hardfork our*/
    /*current service node operators will need to provide their own BLS keys, the foundation*/
    /*will take that list and initialise the list so that the network can immediately start on*/
    /*hardfork.*/

    function seedPublicKeyList(uint256[] calldata pkX, uint256[] calldata pkY, uint256[] calldata amounts) public onlyOwner {
        if (pkX.length != pkY.length || pkX.length != amounts.length) revert ArrayLengthMismatch();
        uint64 lastServiceNode = serviceNodes[LIST_END].previous;
        uint256 sumAmounts;

        for(uint256 i = 0; i < pkX.length; i++) {
            BN256G1.G1Point memory pubkey = BN256G1.G1Point(pkX[i], pkY[i]);
            uint64 serviceNodeID = serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)];
            if(serviceNodeID != 0) revert BLSPubkeyAlreadyExists(serviceNodeID);

            uint64 previous = serviceNodes[LIST_END].previous;

            /*serviceNodes[nextServiceNodeID] = ServiceNode(previous, recipient, pubkey, LIST_END);*/
            serviceNodes[previous].next = nextServiceNodeID;
            serviceNodes[nextServiceNodeID].previous = previous;
            serviceNodes[nextServiceNodeID].pubkey = pubkey;
            serviceNodes[nextServiceNodeID].deposit = amounts[i];
            sumAmounts = sumAmounts + amounts[i];

            serviceNodeIDs[BN256G1.getKeyForG1Point(pubkey)] = nextServiceNodeID;

            if (serviceNodes[LIST_END].next != LIST_END) {
                _aggregate_pubkey = BN256G1.add(_aggregate_pubkey, pubkey);
            } else {
                _aggregate_pubkey = pubkey;
            }

            emit NewSeededServiceNode(nextServiceNodeID, pubkey);
            lastServiceNode = nextServiceNodeID;
            nextServiceNodeID++;
        }

        serviceNodes[lastServiceNode].next = LIST_END;
        serviceNodes[LIST_END].previous = lastServiceNode;

    }

    // ECHIDNA - Fuss testing
}
