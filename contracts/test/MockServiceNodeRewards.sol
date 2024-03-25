// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/Pairing.sol";

/// @title Mock Service Node Rewards Contract for Testing
contract MockServiceNodeRewards is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public designatedToken;

    uint64 public nextServiceNodeID = 1;
    uint256 public totalNodes = 0;
    uint256 public blsNonSignerThreshold = 0;
    uint256 public stakingRequirement;

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

    constructor(address _token, uint256 _stakingRequirement) Ownable(msg.sender) {
        designatedToken = IERC20(_token);
        stakingRequirement = _stakingRequirement;
    }

    function addBLSPublicKey(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) public {
        serviceNodes[nextServiceNodeID] = ServiceNode(0,0, msg.sender, BN256G1.G1Point(0,0), 0, stakingRequirement);
        nextServiceNodeID++;
        totalNodes++;
        SafeERC20.safeTransferFrom(designatedToken, msg.sender, address(this), stakingRequirement);
    }

    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256, uint256, uint256, uint256, uint256, uint256, uint64[] memory) external {
        recipients[serviceNodes[serviceNodeID].recipient].rewards += serviceNodes[serviceNodeID].deposit;
        delete serviceNodes[serviceNodeID];
        totalNodes--;
    }

    function claimRewards() public {
        recipients[msg.sender].rewards += 50;
        uint256 amount = recipients[msg.sender].rewards - recipients[msg.sender].claimed;
        require(amount > 0, "No rewards to claim");
        recipients[msg.sender].claimed += amount;
        SafeERC20.safeTransfer(designatedToken, msg.sender, amount);
    }
}

