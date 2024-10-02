// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "./ServiceNodeContribution.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "./interfaces/IServiceNodeContributionFactory.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceNodeContributionFactory is IServiceNodeContributionFactory {
    IERC20              public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;
    uint256             public immutable maxContributors;

    /// Tracks the contribution contracts that have been deployed from this
    /// factory
    mapping(address => bool) public deployedContracts;

    // Events
    event NewServiceNodeContributionContract(address indexed contributorContract, uint256 serviceNodePubkey);

    constructor(address _stakingRewardsContract) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        SENT                   = IERC20(stakingRewardsContract.designatedToken());
        maxContributors        = stakingRewardsContract.maxContributors();
    }

    function deploy(BN256G1.G1Point calldata key,
                    IServiceNodeRewards.BLSSignatureParams calldata sig,
                    IServiceNodeRewards.ServiceNodeParams calldata params,
                    IServiceNodeRewards.ReservedContributor[] calldata reserved,
                    bool manualFinalize
    ) public {
        ServiceNodeContribution newContract = new ServiceNodeContribution(
            address(stakingRewardsContract),
            maxContributors,
            key,
            sig,
            params,
            reserved,
            manualFinalize
        );

        deployedContracts[address(newContract)] = true;
        emit NewServiceNodeContributionContract(address(newContract), params.serviceNodePubkey);
    }

    function owns(address contractAddress) external view returns (bool) {
        return deployedContracts[contractAddress];
    }
}
