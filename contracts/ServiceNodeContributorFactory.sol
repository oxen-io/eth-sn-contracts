// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./ServiceNodeContribution.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceNodeContributorFactory {
    IERC20 public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;
    uint256 public immutable maxContributors;

    // TODO sean how best to keep track of the state of these contracts, and prevent this from infinitely growing 
    address[] public serviceNodesAwaitingContribution;

    // EVENTS
    event NewServiceNodeContributionContract(address indexed contributorContract, uint256 serviceNodePubkey);

    constructor(address _stakingRewardsContract, uint256 _maxContributors) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        SENT = IERC20(stakingRewardsContract.designatedToken());
        maxContributors = _maxContributors;
    }

    function deployContributorContract(uint256 pkX, uint256 pkY, uint256 serviceNodePubkey, uint256 feePercentage) public {
        ServiceNodeContribution newContract = new ServiceNodeContribution(address(stakingRewardsContract), maxContributors, pkX, pkY, serviceNodePubkey, feePercentage);
        serviceNodesAwaitingContribution.push(address(newContract));
        emit NewServiceNodeContributionContract(address(newContract), serviceNodePubkey);
    }
}

