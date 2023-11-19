// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "hardhat/console.sol";

//INHERIT BN curve libraries
contract ServiceNodeRewards is Ownable {
    using SafeERC20 for IERC20;
    ERC20 public immutable designatedToken;
    ERC20 public immutable foundationPool;

    uint public nextServiceNodeID;
    uint64 public constant LIST_END = type(uint64).max;

    string immutable proofOfPossessionTag = "BLS_SIG_TRYANDINCREMENT_POP" + block.chainid + address(this);
    string immutable messageTag = "BLS_SIG_TRYANDINCREMENT_REWARD" + block.chainid + address(this);
    string immutable removalTag = "BLS_SIG_TRYANDINCREMENT_REMOVE" + block.chainid + address(this);
    string immutable liquidateTag = "BLS_SIG_TRYANDINCREMENT_LIQUIDATE" + block.chainid + address(this);

    uint256 stakingRequirement;
    uint256 liquidatorRewardRatio;
    uint256 poolShareOfLiquidationRatio;
    uint256 recipientRatio;

    constructor(address _token, uint256 _stakingRequirement, uint256 _liquidatorRewardRatio, uint256 _poolShareofLiquidationRatio, uint256 _recipientRatio) {
        designatedToken = IERC20(_token);
        stakingRequirement = _stakingRequirement;

        poolShareOfLiquidationRatio = _poolShareOfLiquidationRatio;
        liquidatorRewardRatio = _liquidatorRewardRatio;
        recipientRatio = _recipientRatio;

        serviceNodes[LIST_END].previous = LIST_END;
        serviceNodes[LIST_END].next = LIST_END;
    }

    struct ServiceNode {
        uint64 previous;
        address recipient;
        G1Point pubkey;
        uint64 next;
        uint64 leaveRequestTimestamp;
        uint256 deposit;
    }

    struct Recipient {
        uint256 rewards;
        uint256 claimed;
    }

    mapping(uint64 => ServiceNode) public serviceNodes;
    mapping(address => Recipient) public recipients;
    mapping(G1Point => uint64) public serviceNodeIDs;

    G1Point _aggregate_pubkey;

    // EVENTS
    event RewardsBalanceUpdated(address indexed recipientAddress, uint256 amount, uint256 previousBalance);
    event RewardsClaimed(address indexed recipientAddress, uint256 amount);
    event ServiceNodeRemovalRequest(uint64 indexed serviceNodeID, address recipient, G1Point pubkey);
    event ServiceNodeRemoval(uint64 indexed serviceNodeID, address recipient, G1Point pubkey);
    event ServiceNodeLiquidated(uint64 indexed serviceNodeID, address recipient, G1Point pubkey);

    // ERRORS

    error RecipientAddressDoesNotMatch(address expectedRecipient, address providedRecipient, uint256 serviceNodeID);

    // CLAIMING REWARDS

    // TODO define encoding/decoding structure of message
    function updateRewardsBalance(uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint256 message, uint64[] memory ids) public {
        G2Point memory signature = G2Point([sigs1,sigs0],[sigs3,sigs2]);
        G1Point memory pubkey;
        for(uint256 i = 0; i < ids.length; i++) {
            pubkey = add(pubkey, validators[ids[i]].pubkey);
        }
        pubkey = add(_aggregate_pubkey, negate(pubkey));

        G2Point memory Hm = hashToG2(message);
        require(pairing2(P1(), signature, negate(pubkey), Hm), "Invalid BLS Signature");
        // TODO Validate that the message is for you
        recipientAddress = something();
        recipientAmount = something();
        // TODO Update balance
        uint256 previousBalance = recipients[recipientAddress].rewards
        recipients[recipientAddress].rewards = recipientAmount;
        emit RewardsBalanceUpdated(recipientAddress, recipientAmount, previousBalance)
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
        _addBLSPublicKey(pkX, pkY, stakingRequirement, sigs0, sigs1, sigs2, sigs3, msg.sender);
    }

    function _addBLSPublicKey(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, address recipient) internal {
        G1Point memory pubkey = G1Point(pkX, pkY);
        uint64 serviceNodeID = serviceNodeIDs[pubkey];
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

        serviceNodeIDs[pubkey] = nextServiceNodeID;

        if (serviceNodes[LIST_END].next != LIST_END) {
            _aggregate_pubkey = add(_aggregate_pubkey, pubkey);
        } else {
            _aggregate_pubkey = pubkey;
        }
        // TODO we also need service node public key
        emit newServiceNode(nextServiceNodeID, pubkey, recipient);
        nextServiceNodeID++;
        SafeERC20.safeTransferFrom(designatedToken, recipient, address(this), stakingRequirement);
    }

    // Proof of possession tag: "BLS_SIG_TRYANDINCREMENT_POP" || block.chainid ||  address(this) || PUBKEY
    function validateProofOfPossession(G1Point pubkey, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3) internal {
        G2Point memory Hm = hashToG2(hashToField(proofOfPossessionTag.concat(string(abi.encodePacked(pkX, pkY)))));
        G2Point memory signature = G2Point([sigs1,sigs0],[sigs3,sigs2]);
        require(pairing2(P1(), signature, negate(pubkey), Hm), "Invalid Proof of Possession");
    }

    /*checks*/
    /*effects*/
    /*interactions*/

    // Initiate Remove Public Key
    // Checking proof of possession again
    function _initiateRemoveBLSPublicKey(uint64 serviceNodeID, address recipient) internal {
        address serviceNodeRecipient = serviceNodes[serviceNodeID].recipient;
        if(serviceNodeRecipient == address(0)) revert RecipientAddressNotProvided(serviceNodeID);
        if(serviceNodeRecipient != recipient) revert RecipientAddressDoesNotMatch(serviceNodeRecipient, recipient, serviceNodeID);
        if(serviceNodes[serviceNodeID].leaveRequestTimestamp != 0) revert EarlierLeaveRequestMade(serviceNodeID, recipient);
        serviceNodes[serviceNodeID].leaveRequestTimestamp = block.timestamp;
        emit ServiceNodeRemovalRequest(serviceNodeID, recipient, servicesNodes[serviceNode].pubkey);
    }


    // Remove Public Key
    // Validating Signature from network
    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] memory ids) external {
        //Validating signature
        G2Point memory Hm = hashToG2(hashToField(string.concat(removalTag, string(serviceNodeID)))));
        G1Point memory pubkey;
        for(uint256 i = 0; i < ids.length; i++) {
            pubkey = add(pubkey, validators[ids[i]].pubkey);
        }
        pubkey = add(_aggregate_pubkey, negate(pubkey));

        G2Point memory Hm = hashToG2(message);
        require(pairing2(P1(), signature, negate(pubkey), Hm), "Invalid BLS Signature");

        _removeBLSPublicKey(serviceNodeID);
    }

    function removeBLSPublicKeyAfterWaitTime(uint64 serviceNodeID) external {
        uint256 timestamp = serviceNodes[serviceNodeID].leaveRequestTimestamp + MAX_WAIT_TIME;
        if(block.timestamp < timestamp) revert LeaveRequestTooEarly(serviceNodeID, timestamp);
        _removeBLSPublicKey(serviceNodeID);
    }

    function _removeBLSPublicKey(uint64 serviceNodeID) internal {
        address serviceNodeRecipient = serviceNodes[serviceNodeID].recipient;
        uint64 previousServiceNode = serviceNodes[serviceNodeID].previous
        uint64 nextServiceNode = serviceNodes[serviceNodeID].next
        if (nextServiceNode == 0) revert ServiceNodeDoesntExist(serviceNodeID);

        serviceNodes[previousServiceNodes].next = nextServiceNode;
        serviceNodes[nextServiceNodes].previous = previousServiceNode;

        G1Point memory pubkey = G1Point(serviceNodes[serviceNodeID].pubkey.X, serviceNodes[serviceNodeID].pubkey.Y);

        _aggregate_pubkey = add(_aggregate_pubkey, negate(pubkey));

        delete serviceNodes[serviceNodeID].previous;
        delete serviceNodes[serviceNodeID].recipient;
        delete serviceNodes[serviceNodeID].next;
        delete serviceNodes[serviceNodeID].pubkey.X;
        delete serviceNodes[serviceNodeID].pubkey.Y;

        delete serviceNodeIDs[pubkey];

        emit ServiceNodeRemoval(serviceNodeID, servicesNodes[serviceNode].recipient, servicesNodes[serviceNode].pubkey);
    }

    // Liquidate Public Key
    function liquidateBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] memory ids) external {
        //Validating signature
        G2Point memory Hm = hashToG2(hashToField(string.concat(liquidateTag, string(serviceNodeID)))));
        G1Point memory pubkey;
        for(uint256 i = 0; i < ids.length; i++) {
            pubkey = add(pubkey, validators[ids[i]].pubkey);
        }
        pubkey = add(_aggregate_pubkey, negate(pubkey));

        G2Point memory Hm = hashToG2(message);
        require(pairing2(P1(), signature, negate(pubkey), Hm), "Invalid BLS Signature");
        _removeBLSPublicKey(serviceNodeID);

        uint256 ratioSum = poolShareOfLiquidationRatio + liquidatorRewardRatio + recipientRatio;
        uint256 deposit = validators[serviceNodeID].deposit;

        if (liquidatorRewardRatio > 0)
            SafeERC20.safeTransfer(designatedToken, msg.sender, deposit * liquidatorRewardRatio/ratioSum);
        if (poolShareOfLiquidationRatio > 0)
            SafeERC20.safeTransfer(designatedToken, foundationPool, deposit * poolShareOfLiquidationRatio/ratioSum);
        emit ServiceNodeLiquidated(serviceNodeID, servicesNodes[serviceNode].recipient, servicesNodes[serviceNode].pubkey);
    }


    // seedPublicKeyList:
    /*An owner guarded function to set up the initial public key list. Before the hardfork our*/
    /*current service node operators will need to provide their own BLS keys, the foundation*/
    /*will take that list and initialise the list so that the network can immediately start on*/
    /*hardfork.*/

    function seedPublicKeyList(uint256[] pkX, uint256[] pkY, []uint256 amounts) public onlyOwner {
        require(pkX.length() == pkY.length() && pkX.length() == amounts.length())
        uint64 lastServiceNode = serviceNodes[LIST_END].previous;
        uint256 sumAmounts;

        for(uint256 i = 0; i < pkX.length(); i++) {
            G1Point memory pubkey = G1Point(pkX[i], pkY[i]);
            uint64 serviceNodeID = serviceNodeIDs[pubkey];
            if(serviceNodeID != 0) revert BLSPubkeyAlreadyExists(serviceNodeID);

            uint64 previous = serviceNodes[LIST_END].previous;

            /*serviceNodes[nextServiceNodeID] = ServiceNode(previous, recipient, pubkey, LIST_END);*/
            serviceNodes[previous].next = nextServiceNodeID;
            serviceNodes[nextServiceNodeID].previous = previous;
            serviceNodes[nextServiceNodeID].pubkey = pubkey;
            serviceNodes[nextServiceNodeID].deposit = amounts[i];
            sumAmounts = sumAmounts + amounts[i];

            serviceNodeIDs[pubkey] = nextServiceNodeID;

            if (serviceNodes[LIST_END].next != LIST_END) {
                _aggregate_pubkey = add(_aggregate_pubkey, pubkey);
            } else {
                _aggregate_pubkey = pubkey;
            }

            // TODO we also need service node public key
            emit newServiceNode(nextServiceNodeID, pubkey, recipient);
            lastServiceNode = nextServiceNodeID;
            nextServiceNodeID++;
        }

        serviceNodes[lastServiceNode].next = LIST_END;
        serviceNodes[LIST_END].previous = lastServiceNode;

    }

    // ECHIDNA - Fuss testing
}
