// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "../libraries/Shared.sol";
import "../interfaces/ITokenVestingStaking.sol";
import "../interfaces/IServiceNodeContributionFactory.sol";
import "../interfaces/IServiceNodeContribution.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TokenVestingStaking
/// @dev A token holder contract that that vests its balance of any ERC20 token to the beneficiary.
///      Validator lockup - stakable. Nothing unlocked until end of contract where everything
///      unlocks at once. All funds can be staked during the vesting period.
///      If revoked send all funds to revoker and block beneficiary releases indefinitely.
///      Any staked funds at the moment of revocation can be retrieved by the revoker upon unstaking.
///
///      The vesting schedule is time-based (i.e. using block timestamps as opposed to e.g. block numbers), and
///      is therefore sensitive to timestamp manipulation (which is something miners can do, to a certain degree).
///      Therefore, it is recommended to avoid using short time durations (less than a minute).
contract TokenVestingStaking is ITokenVestingStaking, Shared {
    using SafeERC20 for IERC20;

    /// Beneficiary of tokens after they are released. It can be transferrable.
    address                         public           beneficiary;
    /// Address that has permissions to can cancel the vesting and withdraw any
    /// unvested tokens
    address                         public           revoker;
    bool                            public immutable transferableBeneficiary;

    /// Durations and timestamps are expressed in UNIX time, the same units as block.timestamp.
    uint256                         public immutable start;
    uint256                         public immutable end;

    /// solhint-disable-next-line var-name-mixedcase
    IERC20                          public immutable SENT;

    /// The contract that holds the reference addresses for staking purposes.
    IServiceNodeRewards             public immutable rewardsContract;
    bool                            public           revoked;

    /// The contract that deploys multi contributor contracts
    IServiceNodeContributionFactory public contributionFactory;

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
        IServiceNodeContributionFactory contributionFactory_,
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
        contributionFactory     = contributionFactory_;
        SENT                    = sent_;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                 Rewards contract functions               //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function addBLSPublicKey(
        BN256G1.G1Point calldata blsPubkey,
        IServiceNodeRewards.BLSSignatureParams calldata blsSignature,
        IServiceNodeRewards.ServiceNodeParams calldata serviceNodeParams,
        address addrToReceiveStakingRewards
    ) external onlyBeneficiary notRevoked afterStart {
        require(addrToReceiveStakingRewards != address(0), "Rewards can not be paid to the zero-address");

        // NOTE: Configure custom beneficiary for investor
        uint256 stakingRequirement                            = rewardsContract.stakingRequirement();
        IServiceNodeRewards.Contributor[] memory contributors = new IServiceNodeRewards.Contributor[](1);
        contributors[0] = IServiceNodeRewards.Contributor(IServiceNodeRewards.Staker(/*addr*/ address(this),
                                                                                     /*beneficiary*/ addrToReceiveStakingRewards),
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

    function contributeFunds(address contributionContract,
                             uint256 amount,
                             address addrToReceiveStakingRewards) external onlyBeneficiary notRevoked afterStart {
        // NOTE: Retrieve contract
        bool contractDeployed                 = contributionFactory.owns(contributionContract);
        IServiceNodeContribution contribution = IServiceNodeContribution(contributionContract);
        require(contractDeployed, "Contract address is not a valid multi-contributor SN contract");

        // NOTE: Setup the beneficiary to payout the rewards to
        IServiceNodeContribution.BeneficiaryData memory beneficiaryData;
        beneficiaryData.setBeneficiary = true;
        beneficiaryData.beneficiary    = addrToReceiveStakingRewards;

        // NOTE: Approve and contribute funds
        SENT.approve(contributionContract, amount);
        contribution.contributeFunds(amount, beneficiaryData);
    }

    function withdrawContribution(address snContribAddr) external override onlyBeneficiary notRevoked afterStart {
        // NOTE: Retrieve contract
        bool contractDeployed              = contributionFactory.owns(snContribAddr);
        require(contractDeployed, "Contract address is not a valid multi-contributor SN contract");
        IServiceNodeContribution snContrib = IServiceNodeContribution(snContribAddr);
        snContrib.withdrawContribution();
    }

    function updateContributionFactory(address factoryAddr) external override onlyRevoker notRevoked nzAddr(factoryAddr) {
        contributionFactory = IServiceNodeContributionFactory(factoryAddr);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //             Investor contract functions                  //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function release(IERC20 token) external override onlyBeneficiary notRevoked {
        uint256 unreleased = _releasableAmount(token);
        require(unreleased > 0, "Vesting: no tokens are due");

        emit TokensReleased(token, unreleased);

        token.safeTransfer(beneficiary, unreleased);
    }

    function revoke(IERC20 token) external override onlyRevoker notRevoked {
        require(block.timestamp <= end, "Vesting: vesting expired");

        uint256 balance = token.balanceOf(address(this));
        uint256 unreleased = _releasableAmount(token);
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

    /// @dev Calculates the amount that has already vested but hasn't been released yet.
    /// @param token ERC20 token which is being vested.
    function _releasableAmount(IERC20 token) private view returns (uint256) {
        return block.timestamp < end ? 0 : token.balanceOf(address(this));
    }

    function transferBeneficiary(address beneficiary_) external override onlyBeneficiary nzAddr(beneficiary_) {
        require(transferableBeneficiary, "Vesting: beneficiary not transferrable");
        emit BeneficiaryTransferred(beneficiary, beneficiary_);
        beneficiary = beneficiary_;
    }

    function transferRevoker(address revoker_) external override onlyRevoker nzAddr(revoker_) {
        emit RevokerTransferred(revoker, revoker_);
        revoker = revoker_;
    }

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
}
