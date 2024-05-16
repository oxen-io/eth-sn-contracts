// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./ServiceNodeContribution.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceNodeContributionFactory {
    IERC20 public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;
    uint256 public immutable maxContributors;

    // EVENTS
    event NewServiceNodeContributionContract(address indexed contributorContract, uint256 serviceNodePubkey);

    constructor(address _stakingRewardsContract) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        SENT = IERC20(stakingRewardsContract.designatedToken());
        maxContributors = stakingRewardsContract.maxContributors();
    }

    function deployContributionContract(
        BN256G1.G1Point memory blsPubkey,
        IServiceNodeRewards.ServiceNodeParams memory serviceNodeParams
    ) public {
        ServiceNodeContribution newContract = new ServiceNodeContribution(
            address(stakingRewardsContract),
            maxContributors,
            blsPubkey,
            serviceNodeParams
        );
        emit NewServiceNodeContributionContract(address(newContract), serviceNodeParams.serviceNodePubkey);
    }
}
