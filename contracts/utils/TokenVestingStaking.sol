// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "../libraries/Shared.sol";
import "../interfaces/ITokenVestingStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TokenVestingStaking
/// @notice See `ITokenVestingStaking`
/// @dev A token holder contract that vests its ERC20 token to the beneficiary.
/// All tokens are locked until the end of the contract where the balance is
/// released. All tokens can be staked to solo and multi-contribution nodes
/// during the vesting period from this contract's balance.
///
/// If the contract is revoked, all funds are transferred to the revoker and the
/// contract is halted. Staked funds at revocation can be retrieved by the
/// revoker upon unstaking.
///
/// The vesting schedule is time-based (i.e. using block timestamps as opposed
/// to e.g. block numbers) and is therefore sensitive to timestamp manipulation
/// (which is something miners can do, to a certain degree). Therefore, it is
/// recommended to avoid using short time durations (less than a minute).
contract TokenVestingStaking is ITokenVestingStaking, Shared {

    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                      Modifiers                           //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @dev Ensure that the caller is the beneficiary address
    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "Vesting: not the beneficiary");
        _;
    }

    /// @dev Ensure that the caller is the revoker address
    modifier onlyRevoker() {
        require(msg.sender == revoker, "Vesting: not the revoker");
        _;
    }

    modifier notRevoked() {
        require(!revoked, "Vesting: token revoked");
        _;
    }

    modifier afterStart() {
        require(block.timestamp >= start, "Vesting: not started");
        _;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                     Variables                            //
    //                                                          //
    //////////////////////////////////////////////////////////////

    // Vesting
    address                         public           beneficiary;
    address                         public           revoker;
    bool                            public immutable transferableBeneficiary;
    uint256                         public immutable start;
    uint256                         public immutable end;
    bool                            public           revoked;

    // Contracts
    /// solhint-disable-next-line var-name-mixedcase
    IERC20                          public immutable SENT;
    IServiceNodeRewards             public immutable rewardsContract;
    IServiceNodeContributionFactory public           snContribFactory;

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @param beneficiary_ Address of the beneficiary to whom vested tokens
    /// are transferred
    /// @param revoker_ The person with the power to revoke the vesting.
    /// Setting the zero address means it is not revocable.
    /// @param start_ The unix time when the beneficiary can start staking the
    /// tokens.
    /// @param end_ The unix time of the end of the vesting period, everything
    /// withdrawable after
    /// @param transferableBeneficiary_ Whether the beneficiary address can be
    /// transferred
    /// @param rewardsContract_ The SENT staking rewads contract that can
    /// be interacted with
    /// @param sent_ The SENT token address.
    constructor(
        address beneficiary_,
        address revoker_,
        uint256 start_,
        uint256 end_,
        bool transferableBeneficiary_,
        IServiceNodeRewards rewardsContract_,
        IServiceNodeContributionFactory snContribFactory_,
        IERC20 sent_
    ) nzAddr(beneficiary_) nzAddr(address(rewardsContract_)) nzAddr(address(sent_)) {
        require(start_ <= end_, "Vesting: start_ after end_");
        require(block.timestamp < start_, "Vesting: start before current time");

        beneficiary             = beneficiary_;
        revoker                 = revoker_;
        start                   = start_;
        end                     = end_;
        transferableBeneficiary = transferableBeneficiary_;
        rewardsContract         = rewardsContract_;
        snContribFactory        = snContribFactory_;
        SENT                    = sent_;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                 Rewards contract functions               //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function addBLSPublicKey(
        BN256G1.G1Point calldata blsPubkey,
        IServiceNodeRewards.BLSSignatureParams calldata blsSignature,
        IServiceNodeRewards.ServiceNodeParams calldata serviceNodeParams,
        address addrToReceiveRewards
    ) external onlyBeneficiary notRevoked afterStart {
        require(addrToReceiveRewards != address(0), "Rewards can not be paid to the zero-address");

        // NOTE: Configure custom beneficiary for investor
        uint256 stakingRequirement                            = rewardsContract.stakingRequirement();
        IServiceNodeRewards.Contributor[] memory contributors = new IServiceNodeRewards.Contributor[](1);
        contributors[0] = IServiceNodeRewards.Contributor(IServiceNodeRewards.Staker(/*addr*/ address(this),
                                                                                     /*beneficiary*/ addrToReceiveRewards),
                                                                                     stakingRequirement);

        // NOTE: Allow staking requirement to be transferred
        SENT.approve(address(rewardsContract), stakingRequirement);

        // NOTE: Register node
        rewardsContract.addBLSPublicKey(blsPubkey, blsSignature, serviceNodeParams, contributors);
    }

    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) external onlyBeneficiary notRevoked afterStart {
        rewardsContract.initiateRemoveBLSPublicKey(serviceNodeID);
    }

    function claimRewards() external onlyBeneficiary notRevoked afterStart {
        rewardsContract.claimRewards();
    }

    function claimRewards(uint256 amount) external onlyBeneficiary notRevoked afterStart {
        rewardsContract.claimRewards(amount);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //         Multi-contributor SN contract functions          //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function getContributionContract(address contractAddr) private view returns (IServiceNodeContribution result) {
        // NOTE: Retrieve contract
        bool contractDeployed = snContribFactory.owns(contractAddr);
        result                = IServiceNodeContribution(contractAddr);
        require(contractDeployed, "Contract address is not a valid multi-contributor SN contract");
    }

    function contributeFunds(address snContribAddr,
                             uint256 amount,
                             address addrToReceiveRewards) external onlyBeneficiary notRevoked afterStart {
        require(addrToReceiveRewards != address(0), "Rewards can not be paid to the zero-address");

        // NOTE: Retrieve contract
        IServiceNodeContribution snContrib = getContributionContract(snContribAddr);

        // NOTE: Setup the beneficiary to payout the rewards to
        IServiceNodeContribution.BeneficiaryData memory beneficiaryData;
        beneficiaryData.setBeneficiary = true;
        beneficiaryData.beneficiary    = addrToReceiveRewards;

        // NOTE: Approve and contribute funds
        SENT.approve(snContribAddr, amount);
        snContrib.contributeFunds(amount, beneficiaryData);
    }

    function withdrawContribution(address snContribAddr) external override onlyBeneficiary notRevoked afterStart {
        // NOTE: Retrieve contract
        IServiceNodeContribution snContrib = getContributionContract(snContribAddr);
        snContrib.withdrawContribution();
    }

    function updateBeneficiary(address snContribAddr,
                               address addrToReceiveRewards) external onlyBeneficiary notRevoked afterStart {
        require(addrToReceiveRewards != address(0), "Rewards can not be paid to the zero-address");
        IServiceNodeContribution snContrib = getContributionContract(snContribAddr);
        snContrib.updateBeneficiary(addrToReceiveRewards);
    }

    function updateContributionFactory(address factoryAddr) external override onlyRevoker notRevoked nzAddr(factoryAddr) {
        snContribFactory = IServiceNodeContributionFactory(factoryAddr);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //             Investor contract functions                  //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @dev Calculates the amount that has already vested but hasn't been released yet.
    /// @param token ERC20 token which is being vested.
    function releasableAmount(IERC20 token) private view returns (uint256) {
        return block.timestamp < end ? 0 : token.balanceOf(address(this));
    }

    function release(IERC20 token) external override onlyBeneficiary notRevoked {
        uint256 unreleased = releasableAmount(token);
        require(unreleased > 0, "Vesting: no tokens are due");

        emit TokensReleased(token, unreleased);

        token.safeTransfer(beneficiary, unreleased);
    }

    function revoke(IERC20 token) external override onlyRevoker notRevoked {
        require(block.timestamp <= end, "Vesting: vesting expired");

        uint256 balance = token.balanceOf(address(this));
        uint256 unreleased = releasableAmount(token);
        uint256 refund = balance - unreleased;
        revoked = true;

        emit TokenVestingRevoked(token, refund);
        token.safeTransfer(revoker, refund);
    }

    function retrieveRevokedFunds(IERC20 token) external override onlyRevoker {
        require(revoked, "Vesting: token not revoked");
        uint256 balance = token.balanceOf(address(this));

        token.safeTransfer(revoker, balance);
    }

    function transferBeneficiary(address beneficiary_) external override onlyBeneficiary nzAddr(beneficiary_) {
        require(transferableBeneficiary, "Vesting: beneficiary not transferable");
        emit BeneficiaryTransferred(beneficiary, beneficiary_);
        beneficiary = beneficiary_;
    }

    function transferRevoker(address revoker_) external override onlyRevoker nzAddr(revoker_) {
        emit RevokerTransferred(revoker, revoker_);
        revoker = revoker_;
    }
}
