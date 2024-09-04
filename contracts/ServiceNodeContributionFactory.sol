// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "./ServiceNodeContribution.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "./interfaces/IServiceNodeContributionFactory.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceNodeContributionFactory is IServiceNodeContributionFactory {
    IERC20 public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;
    uint256 public immutable maxContributors;
    mapping(address => bool) public deployedContracts;

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
        deployedContracts[address(newContract)] = true;
        emit NewServiceNodeContributionContract(address(newContract), serviceNodeParams.serviceNodePubkey);
    }

    // Function to check if a contract has been deployed
    function isContractDeployed(address contractAddress) public view returns (bool) {
        return deployedContracts[contractAddress];
    }
}
