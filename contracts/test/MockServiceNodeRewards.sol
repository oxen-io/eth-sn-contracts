// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IServiceNodeRewards.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/Pairing.sol";

/// @title Mock Service Node Rewards Contract for Testing
//contract MockServiceNodeRewards is Ownable, IServiceNodeRewards {
contract MockServiceNodeRewards is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public designatedToken;

    uint64 public nextServiceNodeID = 1;
    uint256 public totalNodes = 0;
    uint256 public constant blsNonSignerThreshold = 0;
    uint256 private constant _maxContributors = 10;
    uint256 public stakingRequirement;

    mapping(uint64 => IServiceNodeRewards.ServiceNode) _serviceNodes;
    mapping(address => IServiceNodeRewards.Recipient) public recipients;

    constructor(address _token, uint256 _stakingRequirement) Ownable(msg.sender) {
        designatedToken = IERC20(_token);
        stakingRequirement = _stakingRequirement;
    }

    function maxContributors() public view returns (uint256) {
        return _maxContributors;
    }

    function addBLSPublicKey(BN256G1.G1Point calldata pubkey, IServiceNodeRewards.BLSSignatureParams calldata, IServiceNodeRewards.ServiceNodeParams calldata, IServiceNodeRewards.Contributor[] calldata contributors) public {
        _serviceNodes[nextServiceNodeID].operator = msg.sender;
        _serviceNodes[nextServiceNodeID].deposit = stakingRequirement;
        _serviceNodes[nextServiceNodeID].pubkey = pubkey;

        // Initialize the contributors array for the service node
        uint256 contributorsLength = contributors.length;
        require(contributorsLength <= this.maxContributors(), "Exceeds maximum contributors");

        for (uint256 i = 0; i < contributorsLength; i++) {
            //_serviceNodes[nextServiceNodeID].contributors[i] = contributors[i];
            _serviceNodes[nextServiceNodeID].contributors.push(contributors[i]);
        }
        if (contributorsLength == 0) {
            //_serviceNodes[nextServiceNodeID].contributors[0] = IServiceNodeRewards.Contributor(msg.sender, stakingRequirement);
            _serviceNodes[nextServiceNodeID].contributors.push(IServiceNodeRewards.Contributor(msg.sender,stakingRequirement));
        }

        nextServiceNodeID++;
        totalNodes++;
        designatedToken.safeTransferFrom(msg.sender, address(this), stakingRequirement);
    }

    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256, uint256, uint256, uint256, uint256, uint256, uint64[] memory) external {
        recipients[_serviceNodes[serviceNodeID].operator].rewards += _serviceNodes[serviceNodeID].deposit;
        delete _serviceNodes[serviceNodeID];
        totalNodes--;
    }

    function claimRewards() public {
        recipients[msg.sender].rewards += 50;
        uint256 amount = recipients[msg.sender].rewards - recipients[msg.sender].claimed;
        require(amount > 0, "No rewards to claim");
        recipients[msg.sender].claimed += amount;
        SafeERC20.safeTransfer(designatedToken, msg.sender, amount);
    }

    function serviceNodes(uint64 serviceNodeID) external view returns (IServiceNodeRewards.ServiceNode memory) {
        return _serviceNodes[serviceNodeID];
    }

}

