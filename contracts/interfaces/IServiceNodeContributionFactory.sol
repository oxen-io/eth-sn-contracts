// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IServiceNodeRewards.sol";

interface IServiceNodeContributionFactory {
    function SENT() external view returns (IERC20);
    function stakingRewardsContract() external view returns (IServiceNodeRewards);
    function maxContributors() external view returns (uint256);
    function deployedContracts(address) external view returns (bool);

    function deployContributionContract(
        BN256G1.G1Point memory blsPubkey,
        IServiceNodeRewards.ServiceNodeParams memory serviceNodeParams
    ) external;

    function isContractDeployed(address contractAddress) external view returns (bool);
}
