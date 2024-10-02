// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "./libraries/Shared.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Service Node Contribution Contract
///
/// @dev This contract allows for the collection of contributions towards
/// a service node. Operators usually generate one of these smart contracts using
/// the parent factory contract `ServiceNodeContributionFactory` for each service
/// node they start and wish to collateralise with funds from the public.
///
/// Contributors can fund the service node until the staking requirement is met.
/// Once the staking requirement is met, the contract is automatically finalized
/// and send the service node registration `ServiceNodeRewards` contract.
///
/// This contract supports revoking of the contract prior to finalisation,
/// refunding the contribution to the contributors and the operator.
contract ServiceNodeContribution is Shared {
    // Definitions
    using SafeERC20 for IERC20;

    // Track the status of the multi-contribution contract. At any point in the
    // contract's lifetime, `reset` can be invoked to set the contract back to
    // `WaitForOperatorContrib`.
    enum Status {
        // Contract is initialised w/ no contributions. Call `contributeFunds`
        // to transition into `OpenForPublicContrib`
        WaitForOperatorContrib,

        // Contract has been initially funded by operator. Public and reserved
        // contributors can now call `contributeFunds`. When the contract is
        // collaterialised with exactly the staking requirement, the contract
        // transitions into `WaitForFinalized` state.
        OpenForPublicContrib,

        // Operator must invoke `finalizeNode` to transfer the tokens and the
        // node registration details to the `stakingRewardsContract` to
        // transition to `Finalized` state.
        WaitForFinalized,

        // Contract interactions are blocked until `reset` is called.
        Finalized
    }

    struct BeneficiaryData {
        bool setBeneficiary;
        address beneficiary;
    }

    // Staking
    // solhint-disable-next-line var-name-mixedcase
    IERC20                                        public immutable SENT;
    IServiceNodeRewards                           public immutable stakingRewardsContract;
    uint256                                       public immutable stakingRequirement;

    // Service Node
    BN256G1.G1Point                               public blsPubkey;
    IServiceNodeRewards.ServiceNodeParams         public serviceNodeParams;
    IServiceNodeRewards.BLSSignatureParams        public blsSignature;

    // Contributions
    address                                       public immutable operator;
    mapping(address stakerAddr => uint256 amount) public           contributions;
    mapping(address stakerAddr => uint256 amount) public           contributionTimestamp;
    IServiceNodeRewards.Staker[]                  public           contributorAddresses;
    uint256                                       public immutable maxContributors;

    // Reserved Stakes
    mapping(address stakerAddr => uint256 amount) public reservedContributions;
    address[]                                     public reservedContributionsAddresses;

    // Smart Contract
    Status                                        public          status           = Status.WaitForOperatorContrib;
    uint64                                        public constant WITHDRAWAL_DELAY = 1 days;
    uint16                                        public constant MAX_FEE          = 10000;

    // Prevents the contract from automatically invoking `finalize` when a
    // contribution to the contract fulfills the staking requirement. When true,
    // the operator must manually invoke `finalize` which transfers the stake
    // and registers the node to the `stakingRewardsContract`
    //
    // By default, this flag is false which makes the finalize step
    // automatic when the staking requirement is fulfilled (including when
    // a public contributor fulfills the node).
    bool public manualFinalize;

    // Modifers
    modifier onlyOperator() {
        if (msg.sender != operator)
            revert OnlyOperatorIsAuthorised(msg.sender, operator);
        _;
    }

    // Events
    event Finalized(uint256 indexed serviceNodePubkey);
    event NewContribution(address indexed contributor, uint256 amount);
    event OpenForPublicContribution(uint256 indexed serviceNodePubkey, address indexed operator, uint16 fee);
    event Filled(uint256 indexed serviceNodePubkey, address indexed operator);
    event WithdrawContribution(address indexed contributor, uint256 amount);
    event UpdateStakerBeneficiary(address indexed staker, address beneficiary);

    // Errors
    error CalcMinContributionGivenBadContribArgs(uint256 numContributors, uint256 maxNumContributors);
    /// @notice Contract is not in a state where it can accept contributions
    error ContributeFundsNotPossible(Status status);
    error ContributionBelowMinAmount(uint256 contributed, uint256 min);
    error ContributionBelowReservedAmount(uint256 contributed, uint256 reserved);
    error ContributionExceedsStakingRequirement(uint256 totalContributed, uint256 totalReserved, uint256 stakingRequirement);
    error DuplicateAddressInReservedContributor(uint256 index);
    error FeeExceedsPossibleValue(uint16 fee, uint16 max);
    error FeeUpdateNotPossible(Status status);
    error FinalizeNotPossible(Status status);
    error FirstContributionMustBeOperator(address contributor, address operator);

    /// @notice A wallet has attempted to contribute to the contract
    /// before the operator's wallet has contributed.
    error FirstReservedContributorMustBeOperator(uint256 index, address operator);

    /// @notice A wallet has attempted an operation only permitted by the
    /// operator
    error OnlyOperatorIsAuthorised(address addr, address operator);
    error MaxContributorsExceeded(uint256 maxContributors);
    error PubkeyUpdateNotPossible(Status status);
    error RescueBalanceIsEmpty(address token);
    error RescueNotPossible(Status status);
    error ReservedContributorHasZeroAddress(uint256 index);
    error ReservedContributorUpdateNotPossible(Status status);
    error ReservedContributionBelowMinAmount(uint256 index, uint256 contributed, uint256 min);
    error ReservedContributionExceedsStakingRequirement(uint256 index, uint256 contributed, uint256 remaining);

    /// @notice The rewards contract max contributor value has changed and no
    /// longer matches this contract's max contributor value invalidating the
    /// contract.
    ///
    /// The operator or contributors should withdraw their funds and the operator
    /// should deploy another contribution contract to attain a new contract with
    /// the correct values.
    error RewardsContractMaxContributorsChanged(uint256 oldMax, uint256 newMax);

    /// @notice The staking requirement has changed on the rewards contract and
    /// no longer matches this contract's staking requirement.
    ///
    /// See `RewardsContractMaxContributorsChanged` for more info.
    error RewardsContractStakingRequirementChanged(uint256 oldRequirement, uint256 newRequirement);

    /// @notice Updating of beneficiary failed because the wallet that requested
    /// it `nonContributorAddr` is not a contributor for this node.
    error NonContributorUpdatedBeneficiary(address nonContributorAddr);
    error TooManyReservedContributors(uint256 length, uint256 max);
    error WithdrawTooEarly(uint256 contribTime, uint256 blockTime, uint256 delayRequired);

    /// @notice Constructs a multi-contribution node contract for the
    /// specified `_stakingRewardsContract`.
    ///
    /// @dev This contract should typically be invoked from the parent
    /// contribution factory `ServiceNodeContributionFactory`.
    ///
    /// @param _stakingRewardsContract Address of the staking rewards contract.
    /// @param _maxContributors Maximum number of contributors allowed.
    /// @param key 64 byte BLS public key for the node.
    /// @param sig 128 byte BLS proof-of-posession signature that proves the
    /// caller knows the secret component of `key`.
    /// @param params Node registration parameters including the Ed25519 public
    /// key, a signature and the fee the operator is charging.
    /// @param reserved The new array of reserved contributors with their
    /// proportion of stake they must fulfill in the node.
    /// @param _manualFinalize Configure if the contract automatically (or does
    /// not) finalize the contract upon receipt of a contribution that
    /// funds the total required staking requirement of the contract.
    /// Finalisation being the registration of the node on
    /// `stakingRewardsContract`
    constructor(
        address _stakingRewardsContract,
        uint256 _maxContributors,
        BN256G1.G1Point memory key,
        IServiceNodeRewards.BLSSignatureParams memory sig,
        IServiceNodeRewards.ServiceNodeParams memory params,
        IServiceNodeRewards.ReservedContributor[] memory reserved,
        bool _manualFinalize
    ) nzAddr(_stakingRewardsContract) nzUint(_maxContributors) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        stakingRequirement     = stakingRewardsContract.stakingRequirement();
        SENT                   = IERC20(stakingRewardsContract.designatedToken());
        maxContributors        = _maxContributors;
        operator               = tx.origin; // NOTE: Creation is delegated by operator through factory

        BeneficiaryData memory nilContribData;
        _resetUpdateAndContribute(key, sig, params, reserved, _manualFinalize, nilContribData, 0);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Update the flag that allows or disallows the contract from
    /// automatically finalizing the contract when the staking requirement is met.
    ///
    /// This can be called at any point of the contract's lifetime.
    function updateManualFinalize(bool value) external onlyOperator { _updateManualFinalize(value); }

    /// @notice See `updateManualFinalize`
    function _updateManualFinalize(bool value) private {
        manualFinalize = value;
    }

    /// @notice Update the node fee held in this contract.
    ///
    /// This can only be called prior to the operator contributing funds to the
    /// contract or alternatively after they have called `reset`.
    function updateFee(uint16 fee) external onlyOperator { _updateFee(fee); }

    /// @notice See `updateFee`
    function _updateFee(uint16 fee) private {
        if (status != Status.WaitForOperatorContrib)
            revert FeeUpdateNotPossible(status);
        if (fee > MAX_FEE)
            revert FeeExceedsPossibleValue(fee, MAX_FEE);
        serviceNodeParams.fee = fee;
    }

    /// @notice Update the public keys and their proofs held in the contract.
    ///
    /// This can only be called prior to the operator contributing funds to the
    /// contract or alternatively after they have called `reset`.
    ///
    /// @param newBLSPubkey The new 64 byte BLS public key for the node.
    /// @param newBLSSig The new 128 byte BLS proof-of-posession signature that proves
    /// the caller knows the secret component of `key`.
    /// @param ed25519Pubkey The new 32 byte Ed25519 public key for the node.
    /// @param ed25519Sig0 First 32 byte component of the signature for the Ed25519 key.
    /// @param ed25519Sig1 Second 32 byte component of the signature for the Ed25519 key.
    function updatePubkeys(BN256G1.G1Point memory newBLSPubkey,
                           IServiceNodeRewards.BLSSignatureParams memory newBLSSig,
                           uint256 ed25519Pubkey,
                           uint256 ed25519Sig0,
                           uint256 ed25519Sig1) external onlyOperator {
        _updatePubkeys(newBLSPubkey, newBLSSig, ed25519Pubkey, ed25519Sig0, ed25519Sig1);
    }

    /// @notice See `updatePubkeys`
    function _updatePubkeys(BN256G1.G1Point memory newBLSPubkey,
                            IServiceNodeRewards.BLSSignatureParams memory newBLSSig,
                            uint256 ed25519Pubkey,
                            uint256 ed25519Sig0,
                            uint256 ed25519Sig1) private {
        if (status != Status.WaitForOperatorContrib)
            revert PubkeyUpdateNotPossible(status);

        // TODO: Check that the zero signature is rejected
        stakingRewardsContract.validateProofOfPossession(newBLSPubkey, newBLSSig, operator, ed25519Pubkey);

        // NOTE: Update BLS keys
        blsPubkey                               = newBLSPubkey;
        blsSignature                            = newBLSSig;

        // NOTE: Update Ed25519 keys
        serviceNodeParams.serviceNodePubkey     = ed25519Pubkey;
        serviceNodeParams.serviceNodeSignature1 = ed25519Sig0;
        serviceNodeParams.serviceNodeSignature2 = ed25519Sig1;
    }

    /// @notice Update the reservation slots for contributors held in this contract.
    ///
    /// This can only be called prior to the operator contributing funds to the
    /// contract or alternatively after they have called `reset`.
    ///
    /// The list of reservations can be empty which will reset the contract,
    /// deleting any reservation data that is currently held. The list cannot
    /// specify more reservations than `maxContributors` or otherwise the
    /// function reverts.
    ///
    /// @param reserved The new array of reserved contributors with their
    /// proportion of stake they must fulfill in the node.
    function updateReservedContributors(IServiceNodeRewards.ReservedContributor[] memory reserved) external onlyOperator {
        _updateReservedContributors(reserved);
    }

    /// @notice See `updateReservedContributors`
    function _updateReservedContributors(IServiceNodeRewards.ReservedContributor[] memory reserved) private {
        if (status != Status.WaitForOperatorContrib)
            revert ReservedContributorUpdateNotPossible(status);

        // NOTE: Remove old reserved contributions
        {
            uint256 arrayLength = reservedContributionsAddresses.length;
            for (uint256 i = 0; i < arrayLength; i++)
                reservedContributions[reservedContributionsAddresses[i]] = 0;
            delete reservedContributionsAddresses;
        }

        // NOTE: Assign new contributions and verify them
        uint256 remaining = stakingRequirement;

        if (reserved.length > maxContributors)
            revert TooManyReservedContributors(reserved.length, maxContributors);

        for (uint256 i = 0; i < reserved.length; i++) {
            if (i == 0) {
                if (reserved[i].addr != operator)
                    revert FirstReservedContributorMustBeOperator(i, operator);
            }

            if (reserved[i].addr == address(0))
                revert ReservedContributorHasZeroAddress(i);

            if (reservedContributions[reserved[i].addr] != 0)
                revert DuplicateAddressInReservedContributor(i);

            // NOTE: Check contribution meets min requirements and running sum
            // doesn't exceed a full stake
            uint256 minContrib     = calcMinimumContribution(remaining, i, maxContributors);
            uint256 contribAmount  = reserved[i].amount;

            if (contribAmount < minContrib)
                revert ReservedContributionBelowMinAmount(i, contribAmount, minContrib);

            if (remaining < contribAmount)
                revert ReservedContributionExceedsStakingRequirement(i, contribAmount, remaining);

            remaining -= contribAmount;

            // NOTE: Store the reservation in the contract
            reservedContributionsAddresses.push(reserved[i].addr);
            reservedContributions[reserved[i].addr] = contribAmount;
        }
    }

    function updateBeneficiary(address newBeneficiary) external { _updateBeneficiary(msg.sender, newBeneficiary); }

    /// @notice See `updateBeneficiary`
    function _updateBeneficiary(address stakerAddr, address newBeneficiary) private {
        bool updated   = false;
        uint256 length = contributorAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            IServiceNodeRewards.Staker storage staker = contributorAddresses[i];
            if (staker.addr == stakerAddr) {
                updated            = true;
                staker.beneficiary = newBeneficiary;
                break;
            }
        }

        if (!updated)
            revert NonContributorUpdatedBeneficiary(stakerAddr);

        emit UpdateStakerBeneficiary(stakerAddr, newBeneficiary);
    }

    /// @notice Contribute funds to the contract for the node run by
    /// `operator`. The `amount` of SENT token must be at least the
    /// `minimumContribution` or their amount specified in their reserved
    /// contribution (if applicable) otherwise the contribution is reverted.
    ///
    /// Node registration parameters must be assigned prior to the operator
    /// contribution or alternatively after `reset` is invoked.
    ///
    /// The operator must contribute their minimum contribution/reservation
    /// before the public or reserved contributors can contribute to the node.
    /// The minimum an operator can contribute is 25% of the staking requirement
    /// regardless of having a reservation or not.
    ///
    /// @param amount The amount of SENT token to contribute to the contract.
    function contributeFunds(uint256 amount, BeneficiaryData memory data) external { _contributeFunds(msg.sender, data, amount); }

    /// @notice See `contributeFunds`
    function _contributeFunds(address caller, BeneficiaryData memory data, uint256 amount) private {
        if (status != Status.WaitForOperatorContrib && status != Status.OpenForPublicContrib)
            revert ContributeFundsNotPossible(status);

        // NOTE: Check if parent contract invariants changed
        if (maxContributors != stakingRewardsContract.maxContributors())
            revert RewardsContractMaxContributorsChanged(maxContributors, stakingRewardsContract.maxContributors());

        if (stakingRequirement != stakingRewardsContract.stakingRequirement())
            revert RewardsContractMaxContributorsChanged(stakingRequirement, stakingRewardsContract.stakingRequirement());

        // NOTE: Handle operator contribution, initially the operator must contribute to open the
        // contract up to public/reserved contributions.
        if (status == Status.WaitForOperatorContrib) {
            if (caller != operator)
                revert FirstContributionMustBeOperator(caller, operator);
            status = Status.OpenForPublicContrib;
            emit OpenForPublicContribution(serviceNodeParams.serviceNodePubkey, operator, serviceNodeParams.fee);
        }

        // NOTE: Verify the contribution
        uint256 reserved = reservedContributions[caller];
        if (reserved > 0) {
            // NOTE: Remove their contribution from the reservation table
            if (amount < reserved)
                revert ContributionBelowReservedAmount(amount, reserved);
            reservedContributions[caller] = 0;

            // NOTE: Remove contributor from their reservation slot
            uint256 arrayLength = reservedContributionsAddresses.length;
            for (uint256 index = 0; index < arrayLength; index++) {
                if (caller == reservedContributionsAddresses[index]) {
                    reservedContributionsAddresses[index] = reservedContributionsAddresses[arrayLength - 1];
                    reservedContributionsAddresses.pop();
                    break;
                }
            }
        } else {
            // NOTE: Check amount is greater than the minimum contribution only
            // if they have not contributed before (otherwise we allow
            // topping-up of their contribution).
            if (contributions[caller] == 0 && amount < minimumContribution())
                revert ContributionBelowMinAmount(amount, minimumContribution());
        }

        // NOTE: Add the contributor to the contract
        if (contributions[caller] == 0)
            contributorAddresses.push(IServiceNodeRewards.Staker(caller, caller));

        if (data.setBeneficiary)
            _updateBeneficiary(caller, data.beneficiary);

        // NOTE: Update the amount contributed and transfer the tokens
        contributions[caller]         += amount;
        contributionTimestamp[caller]  = block.timestamp;

        // NOTE: Check contract collateralisation _after_ the amount is
        // committed to the contract to ensure contribution sums are all
        // accounted for.
        if ((totalContribution() + totalReservedContribution()) > stakingRequirement)
            revert ContributionExceedsStakingRequirement(totalContribution(), totalReservedContribution(), stakingRequirement);

        if (contributorAddresses.length > maxContributors)
            revert MaxContributorsExceeded(maxContributors);

        emit NewContribution(caller, amount);

        // NOTE: Transfer funds from sender to contract
        SENT.safeTransferFrom(caller, address(this), amount);

        // NOTE: Allow finalizing the node if the staking requirement is met
        if (totalContribution() == stakingRequirement) {
            emit Filled(serviceNodeParams.serviceNodePubkey, operator);
            status = Status.WaitForFinalized;
            if (!manualFinalize) // Auto finalize if allowed
                _finalize();
        }
    }

    /// @notice Activate the node by transferring the registration details and
    /// tokens to the `stakingRewardsContract`.
    ///
    /// After finalisation the contract can be reused by invoking
    /// `reset`.
    function finalize() external onlyOperator { _finalize(); }

    /// @notice See `finalize`
    function _finalize() private {
        if (status != Status.WaitForFinalized)
            revert FinalizeNotPossible(status);

        // NOTE: Finalize the contract
        status = Status.Finalized;
        emit Finalized(serviceNodeParams.serviceNodePubkey);

        uint256 length                                        = contributorAddresses.length;
        IServiceNodeRewards.Contributor[] memory contributors = new IServiceNodeRewards.Contributor[](length);
        for (uint256 i = 0; i < length; i++) {
            IServiceNodeRewards.Staker storage entry = contributorAddresses[i];
            contributors[i]                          = IServiceNodeRewards.Contributor(entry, contributions[entry.addr]);
        }

        // NOTE: Transfer tokens and register the node on the `stakingRewardsContract`
        SENT.approve(address(stakingRewardsContract), stakingRequirement);
        stakingRewardsContract.addBLSPublicKey(blsPubkey, blsSignature, serviceNodeParams, contributors);
    }

    /// @notice Reset the contract allowing it to be reused to re-register the
    /// pre-existing node by refunding and removing all stored contributions.
    ///
    /// This function can be called any point in the lifetime of the contract to
    /// bring it to its initial state. Node parameters (Ed25519 key, sig, fee)
    /// and the BLS key and signature are preserved across reset and can be
    /// updated piecemeal via the `update...` family of functions.
    function reset() external onlyOperator { _reset(); }

    /// @notice See `reset`
    function _reset() private {
        {
            IServiceNodeRewards.Staker[] memory copy = contributorAddresses;
            uint256 length                           = copy.length;
            for (uint256 i = 0; i < length; i++)
                removeAndRefundContributor(copy[i].addr);
            delete contributorAddresses;
        }

        // NOTE: Reset left-over contract variables
        status = Status.WaitForOperatorContrib;

        // NOTE: Remove all reserved contributions
        {
            IServiceNodeRewards.ReservedContributor[] memory zero;
            _updateReservedContributors(zero);
        }
    }

    /// @notice Helper function that invokes a reset and updates all possible
    /// parameters for the registration.
    ///
    /// This function is equivalent to calling in sequence:
    ///
    ///   - `reset`
    ///   - `updatePubkeys`
    ///   - `updateFee`
    ///   - `updateReservedContributors`
    ///   - `updateManualFinalize`
    ///   - `contributeFunds`
    ///
    /// If reserved contributors are not desired, an empty array is accepted.
    ///
    /// If the operator wishes to withhold their initial contribution, a `0`
    /// amount is accepted.
    function resetUpdateAndContribute(BN256G1.G1Point memory key,
                                      IServiceNodeRewards.BLSSignatureParams memory sig,
                                      IServiceNodeRewards.ServiceNodeParams memory params,
                                      IServiceNodeRewards.ReservedContributor[] memory reserved,
                                      bool _manualFinalize,
                                      BeneficiaryData memory benficiaryData,
                                      uint256 amount) external onlyOperator {
        _resetUpdateAndContribute(key, sig, params, reserved, _manualFinalize, benficiaryData, amount);
    }

    /// @notice See `resetUpdateAndContribute`
    function _resetUpdateAndContribute(BN256G1.G1Point memory key,
                                       IServiceNodeRewards.BLSSignatureParams memory sig,
                                       IServiceNodeRewards.ServiceNodeParams memory params,
                                       IServiceNodeRewards.ReservedContributor[] memory reserved,
                                       bool _manualFinalize,
                                       BeneficiaryData memory benficiaryData,
                                       uint256 amount) private {
        _reset();
        _updatePubkeys(key, sig, params.serviceNodePubkey, params.serviceNodeSignature1, params.serviceNodeSignature2);
        _updateFee(params.fee);
        _updateReservedContributors(reserved);
        _updateManualFinalize(_manualFinalize);
        if (amount > 0)
            _contributeFunds(operator, benficiaryData, amount);
    }

    /// @notice Helper function that updates the fee, reserved contributors,
    /// manual finalization and contribution of the node.
    ///
    /// This function is equivalent to calling in sequence:
    ///
    ///   - `reset`
    ///   - `updateFee`
    ///   - `updateReservedContributors`
    ///   - `updateManualFinalize`
    ///   - `contributeFunds`
    ///
    /// If reserved contributors are not desired, the empty array is accepted.
    ///
    /// If the operator wishes to withhold their initial contribution, a `0`
    /// amount is accepted.
    ///
    /// @dev Useful to conduct exactly 1 transaction to re-use a node with new
    /// contributors and maintain the same keys for the node after
    /// a deregistration or exit.
    function resetUpdateFeeReservedAndContribute(uint16 fee,
                                                 IServiceNodeRewards.ReservedContributor[] memory reserved,
                                                 bool _manualFinalize,
                                                 BeneficiaryData calldata benficiaryData,
                                                 uint256 amount) external onlyOperator {
        _reset();
        _updateFee(fee);
        _updateReservedContributors(reserved);
        _updateManualFinalize(_manualFinalize);
        if (amount > 0)
            _contributeFunds(operator, benficiaryData, amount);
    }

    /// @notice Function to allow owner to rescue any ERC20 tokens sent to the
    /// contract after it has been finalized.
    ///
    /// @dev Rescue is only allowed when finalized or no contribution has been
    /// made to the contract so any token balance from contributors are either
    /// absent or have been transferred to the `stakingRewardsContract` and the
    /// remaining tokens can be sent without risking contributor collateral.
    ///
    /// @param tokenAddress The ERC20 token to rescue from the contract.
    function rescueERC20(address tokenAddress) external onlyOperator {
        // NOTE: ERC20 tokens sent to the contract can only be rescued after the
        // contract is finalized or the contract has been reset
        // because:
        //
        //   The contract is not funded by any contributor/operator (e.g: It was
        //   just reset) (status == WaitForOperatorContrib)
        //     OR
        //   The funds have been transferred to the SN rewards contract
        //   (status == Finalized)
        //
        // This allows them to refund any other tokens that might have
        // mistakenly been sent throughout the lifetime of the contract without
        // giving them access to contributor tokens.
        if (status != Status.Finalized && status == Status.WaitForOperatorContrib)
            revert RescueNotPossible(status);

        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        if (balance <= 0)
            revert RescueBalanceIsEmpty(tokenAddress);

        token.safeTransfer(operator, balance);
    }

    /// @notice Allows the contributor or operator to withdraw their contribution
    /// from the contract.

    /// After finalization, the registration is transferred to the
    /// `stakingRewardsContract` and withdrawal by or the operator contributors
    /// must be done through that contract.
    function withdrawContribution() external {
        if (msg.sender == operator) {
            _reset();
            return;
        }

        uint256 timeSinceLastContribution = block.timestamp - contributionTimestamp[msg.sender];
        if (timeSinceLastContribution < WITHDRAWAL_DELAY)
            revert WithdrawTooEarly(contributionTimestamp[msg.sender], block.timestamp, WITHDRAWAL_DELAY);

        uint256 refundAmount = removeAndRefundContributor(msg.sender);
        if (refundAmount > 0)
            emit WithdrawContribution(msg.sender, refundAmount);
    }

    /// @dev Remove the contributor by address specified by `toRemove` from the
    /// smart contract. This updates all contributor related smart contract
    /// variables including the:
    ///
    ///   1) Removing contributor from contribution mapping
    ///   2) Removing their address from the contribution array
    ///   3) Refunding the SENT amount contributed to the contributor
    ///
    /// @return result The amount of SENT refunded for the given `toRemove`
    /// address. If `toRemove` is not a contributor/does not exist, 0 is returned
    /// as the refunded amount.
    function removeAndRefundContributor(address toRemove) private returns (uint256 result) {
        result = contributions[toRemove];
        if (result == 0)
            return result;

        // 1) Removing contributor from contribution mapping
        contributions[toRemove]         = 0;
        contributionTimestamp[toRemove] = 0;

        // 2) Removing their address from the contribution array
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 index = 0; index < arrayLength; index++) {
            if (toRemove == contributorAddresses[index].addr) {
                contributorAddresses[index] = contributorAddresses[arrayLength - 1];
                contributorAddresses.pop();
                break;
            }
        }

        if (status == Status.Finalized) {
            // NOTE: Funds have been transferred out already, we just needed to
            // clean up the contract book-keeping for `toRemove`.
            result = 0;
        } else {
            // 3) Refunding the SENT amount contributed to the contributor
            SENT.safeTransfer(toRemove, result);
        }
        return result;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @notice Calculates the minimum contribution amount given the current
    /// contribution status of the contract.
    ///
    /// @dev The minimum contribution is dynamically calculated based on the
    /// number of contributors and the staking requirement. It returns
    /// math.ceilDiv of the calculation
    ///
    /// @return result The minimum contribution amount.
    function minimumContribution() public view returns (uint256 result) {
        result = calcMinimumContribution(
            stakingRequirement - totalContribution() - totalReservedContribution(),
            contributorAddresses.length + reservedContributionsAddresses.length,
            maxContributors
        );
        return result;
    }

    /// @notice Function to calculate the minimum contribution given the staking
    /// parameters.
    ///
    /// This function reverts if invalid parameters are given such that the
    /// operations would wrap or divide by 0.
    ///
    /// @param contributionRemaining The amount of contribution still available
    /// to be contributed to this contract.
    /// @param numContributors The number of contributors that have contributed
    /// to the contract already including the operator.
    /// @param maxNumContributors The maximum number of contributors allowed to
    /// contribute to this contract.
    function calcMinimumContribution(
        uint256 contributionRemaining,
        uint256 numContributors,
        uint256 maxNumContributors
    ) public pure returns (uint256 result) {
        if (maxNumContributors <= numContributors)
            revert CalcMinContributionGivenBadContribArgs(numContributors, maxNumContributors);

        if (numContributors == 0) {
            result = ((contributionRemaining - 1) / 4) + 1; // math.ceilDiv(25% of requirement)
        } else {
            uint256 slotsRemaining = maxNumContributors - numContributors;
            result = (contributionRemaining - 1) / slotsRemaining + 1;
        }
        return result;
    }

    /// @notice Calculates the minimum operator contribution given the staking
    /// requirement.
    function minimumOperatorContribution(uint256 _stakingRequirement) public pure returns (uint256 result) {
        result = calcMinimumContribution(_stakingRequirement, 0, 1);
        return result;
    }

    /// @dev This function allows unit-tests to query the length without having
    /// to know the storage slot of the array size.
    function contributorAddressesLength() public view returns (uint256 result) {
        result = contributorAddresses.length;
        return result;
    }

    /// @notice Get the contribution by the operator, defined to always be the
    /// first contribution in the contract.
    function operatorContribution() public view returns (uint256 result) {
        result = contributorAddresses.length > 0 ? contributions[contributorAddresses[0].addr] : 0;
        return result;
    }

    /// @notice Access the list of contributor addresses and corresponding contributions.  The
    /// first returned address (if any) is also the operator address.
    function getContributions() public view returns (address[] memory addrs, address[] memory beneficiaries, uint256[] memory contribs) {
        uint256 size = contributorAddresses.length;
        addrs         = new address[](size);
        beneficiaries = new address[](size);
        contribs      = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            IServiceNodeRewards.Staker storage staker = contributorAddresses[i];
            addrs[i]         = staker.addr;
            beneficiaries[i] = staker.beneficiary;
            contribs[i]      = contributions[addrs[i]];
        }
        return (addrs, beneficiaries, contribs);
    }

    /// @notice Sum up all the contributions recorded in the contributors list
    function totalContribution() public view returns (uint256 result) {
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            address entry = contributorAddresses[i].addr;
            result += contributions[entry];
        }
        return result;
    }

    /// @notice Sum up all the reserved contributions recorded in the reserved list
    function totalReservedContribution() public view returns (uint256 result) {
        uint256 arrayLength = reservedContributionsAddresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            address entry = reservedContributionsAddresses[i];
            result += reservedContributions[entry];
        }
        return result;
    }
}
