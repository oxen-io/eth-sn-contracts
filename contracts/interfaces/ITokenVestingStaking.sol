// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IServiceNodeRewards.sol";

interface ITokenVestingStaking {
    event TokensReleased(IERC20 indexed token, uint256 amount);
    event TokenVestingRevoked(IERC20 indexed token, uint256 refund);

    event BeneficiaryTransferred(address oldBeneficiary, address newBeneficiary);
    event RevokerTransferred(address oldRevoker, address newRevoker);

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function addBLSPublicKey(
        BN256G1.G1Point calldata blsPubkey,
        IServiceNodeRewards.BLSSignatureParams calldata blsSignature,
        IServiceNodeRewards.ServiceNodeParams calldata serviceNodeParams
    ) external;

    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) external;

    function claimRewards() external;

    function contributeFunds(address contributionContract, uint256 amount) external;

    function withdrawContribution(address contributionContractAddress) external;

    function release(IERC20 token) external;

    function revoke(IERC20 token) external;

    function updateContributionFactory(address newFactory) external;

    function retrieveRevokedFunds(IERC20 token) external;

    function transferBeneficiary(address beneficiary_) external;

    function transferRevoker(address revoker_) external;

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function getBeneficiary() external view returns (address);

    function getRevoker() external view returns (address);

    function investorServiceNodesLength() external view returns (uint256);
}
