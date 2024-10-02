// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IServiceNodeRewards.sol";

interface IServiceNodeContributionFactory {
    function SENT()                     external view returns (IERC20);
    function stakingRewardsContract()   external view returns (IServiceNodeRewards);
    function maxContributors()          external view returns (uint256);
    function deployedContracts(address) external view returns (bool);

    function deploy(BN256G1.G1Point calldata key,
                    IServiceNodeRewards.BLSSignatureParams calldata sig,
                    IServiceNodeRewards.ServiceNodeParams calldata params,
                    IServiceNodeRewards.ReservedContributor[] calldata reserved,
                    bool manualFinalize) external;

    function owns(address contractAddress) external view returns (bool);
}
