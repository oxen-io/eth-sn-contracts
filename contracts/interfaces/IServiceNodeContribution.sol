// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "./IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IServiceNodeContribution {
    // State-changing functions
    function contributeOperatorFunds(uint256 amount, IServiceNodeRewards.BLSSignatureParams memory _blsSignature) external;
    function contributeFunds(uint256 amount) external;
    function resetContract(uint256 amount) external;
    function updateServiceNodeParams(IServiceNodeRewards.ServiceNodeParams memory newParams) external;
    function updateBLSPubkey(BN256G1.G1Point memory newBlsPubkey) external;
    function rescueERC20(address tokenAddress) external;
    function withdrawContribution() external;
    function cancelNode() external;

    // View functions
    function SENT() external view returns (IERC20);
    function stakingRewardsContract() external view returns (IServiceNodeRewards);
    function stakingRequirement() external view returns (uint256);
    function operator() external view returns (address);
    function blsPubkey() external view returns (uint256, uint256);
    function contributions(address) external view returns (uint256);
    function contributionTimestamp(address) external view returns (uint256);
    function contributorAddresses(uint256) external view returns (address);
    function maxContributors() external view returns (uint256);
    function finalized() external view returns (bool);
    function cancelled() external view returns (bool);
    function minimumContribution() external view returns (uint256);
    function calcMinimumContribution(uint256 contributionRemaining, uint256 numContributors, uint256 maxNumContributors) external pure returns (uint256);
    function minimumOperatorContribution(uint256 _stakingRequirement) external pure returns (uint256);
    function contributorAddressesLength() external view returns (uint256);
    function operatorContribution() external view returns (uint256);
    function totalContribution() external view returns (uint256);
}
