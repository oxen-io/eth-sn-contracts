// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "hardhat/console.sol";

contract ServiceNodeRewards is Ownable {
    using SafeERC20 for IERC20;
    ERC20 public immutable designatedToken;

    string immutable proofOfPossessionTag = "BLS_SIG_TRYANDINCREMENT_POP" + block.chainid + address(this);
    string immutable messageTag = "BLS_SIG_TRYANDINCREMENT_REWARD" + block.chainid + address(this);

    uint256 stakingRequirement;

    constructor(address _token, uint256 _stakingRequirement) {
        designatedToken = IERC20(_token);
        stakingRequirement = _stakingRequirement;
    }

    // To review below here
    struct ServiceNode {
        uint64 previous;
        address recipient;
        G1Point pubkey;
        uint64 next;
    }

    struct Recipient {
        uint256 rewards;
        uint256 claimed;
    }

    mapping(uint64 => ServiceNode) public serviceNodes;
    mapping(address => Recipient) public recipients;

    G1Point _aggregate_pubkey;

    // EVENTS
    event RewardsBalanceUpdated(address indexed recipientAddress, uint256 amount, uint256 previousBalance);
    event RewardsClaimed(address indexed recipientAddress, uint256 amount);

    // ERRORS

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
        validateProofOfPossession(pkX, pkY, sigs0, sigs1, sigs2, sigs3);
        serviceNodes[identifier] = (ServiceNode(previous, recipient, G1Point(pkX, pkY), next));
        if (validators.length == 1) {
            _aggregate_pubkey = validators[validators.length - 1].pubkey;
        } else {
            _aggregate_pubkey = add(_aggregate_pubkey, validators[validators.length - 1].pubkey);
        }
        /*function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {*/
        SafeERC20.safeTransferFrom(designatedToken, recipient, address(this), stakingRequirement);
        emit newValidator(validators.length - 1);
    }

    // Proof of possession tag: "BLS_SIG_TRYANDINCREMENT_POP" || block.chainid ||  address(this) || PUBKEY
    function validateProofOfPossession(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3) internal {
        G1Point memory pubkey = G1Point(pkX, pkY);
        G2Point memory Hm = hashToG2(hashToField(proofOfPossessionTag.concat(string(abi.encodePacked(pkX, pkY)))));
        G2Point memory signature = G2Point([sigs1,sigs0],[sigs3,sigs2]);
        require(pairing2(P1(), signature, negate(pubkey), Hm), "Invalid Proof of Possession");
    }


    /*checks*/
    /*effects*/
    /*interactions*/

    // Initiate Remove Public Key
    // Checking proof of possession again


    // Remove Public Key
    // Validating Signature from network
    function _removeBLSPublicKey(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, address recipient) internal {
    }

    // Liquidate Public Key
    // State

    // seedPublicKeyList:
    /*An owner guarded function to set up the initial public key list. Before the hardfork our*/
    /*current service node operators will need to provide their own BLS keys, the foundation*/
    /*will take that list and initialise the list so that the network can immediately start on*/
    /*hardfork.*/
}
