// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./ServiceNodeContribution.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceNodeContributorFactory {
    IERC20 public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;

    address[] public serviceNodesAwaitingContribution;

    constructor(address _stakingRewardsContract) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        SENT = IERC20(stakingRewardsContract.designatedToken());
    }

    // EVENTS
    event NewServiceNodeContributionContract(address indexed contributorContract, uint256 serviceNodePubkey);

    function deployContributorContract(uint256 pkX, uint256 pkY, uint256 serviceNodePubkey, uint256 feePercentage) public {
        ServiceNodeContribution newContract = new ServiceNodeContribution(address(stakingRewardsContract), pkX, pkY, serviceNodePubkey, feePercentage);
        serviceNodesAwaitingContribution.push(address(newContract));
        emit NewServiceNodeContributionContract(address(newContract), serviceNodePubkey);
    }
}

