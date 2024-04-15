// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IServiceNodeRewards.sol";

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

    mapping(uint64 => IServiceNodeRewards.ServiceNode) public serviceNodes;
    mapping(address => IServiceNodeRewards.Recipient) public recipients;

    constructor(address _token, uint256 _stakingRequirement) Ownable(msg.sender) {
        designatedToken = IERC20(_token);
        stakingRequirement = _stakingRequirement;
    }

    function addBLSPublicKey(BN256G1.G1Point calldata, IServiceNodeRewards.BLSSignatureParams calldata, IServiceNodeRewards.ServiceNodeParams calldata, IServiceNodeRewards.Contributor[] calldata) public {
        serviceNodes[nextServiceNodeID] = IServiceNodeRewards.ServiceNode(0,0, msg.sender, BN256G1.G1Point(0,0), 0, stakingRequirement);
        nextServiceNodeID++;
        totalNodes++;
        designatedToken.safeTransferFrom(msg.sender, address(this), stakingRequirement);
    }

    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256, uint256, uint256, uint256, uint256, uint256, uint64[] memory) external {
        recipients[serviceNodes[serviceNodeID].operator].rewards += serviceNodes[serviceNodeID].deposit;
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

