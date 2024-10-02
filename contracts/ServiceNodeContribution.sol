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

    // Staking
    // solhint-disable-next-line var-name-mixedcase
    IERC20              public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;
    uint256             public immutable stakingRequirement;

    // Service Node
    BN256G1.G1Point                        public blsPubkey;
    IServiceNodeRewards.ServiceNodeParams  public serviceNodeParams;
    IServiceNodeRewards.BLSSignatureParams public blsSignature;

    // Contributions
    address                     public immutable operator;
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public contributionTimestamp;
    address[]                   public contributorAddresses;
    uint256                     public immutable maxContributors;

    // Reserved Stakes
    mapping(address => uint256) public reservedContributions;
    address[]                   public reservedContributionsAddresses;

    // Smart Contract
    Status                      public status                    = Status.WaitForOperatorContrib;
    uint64                      public constant WITHDRAWAL_DELAY = 1 days;

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
        require(msg.sender == operator, "Only the operator can perform this action.");
        _;
    }

    // Events
    event Finalized(uint256 indexed serviceNodePubkey);
    event NewContribution(address indexed contributor, uint256 amount);
    event OpenForPublicContribution(uint256 indexed serviceNodePubkey, address indexed operator, uint16 fee);
    event Filled(uint256 indexed serviceNodePubkey, address indexed operator);
    event WithdrawContribution(address indexed contributor, uint256 amount);

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
    constructor(
        address _stakingRewardsContract,
        uint256 _maxContributors,
        BN256G1.G1Point memory key,
        IServiceNodeRewards.BLSSignatureParams memory sig,
        IServiceNodeRewards.ServiceNodeParams memory params,
        IServiceNodeRewards.Contributor[] memory reserved
    ) nzAddr(_stakingRewardsContract) nzUint(_maxContributors) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        stakingRequirement     = stakingRewardsContract.stakingRequirement();
        SENT                   = IERC20(stakingRewardsContract.designatedToken());
        maxContributors        = _maxContributors;
        operator               = tx.origin; // NOTE: Creation is delegated by operator through factory
        _resetUpdateAndContribute(key, sig, params, reserved, 0);
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
        require(status == Status.WaitForOperatorContrib, "Contract can not accept new fee, already received operator contribution");
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
        require(status == Status.WaitForOperatorContrib, "Contract can not accept new public keys, already received operator contribution");
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
    function updateReservedContributors(IServiceNodeRewards.Contributor[] memory reserved) external onlyOperator {
        _updateReservedContributors(reserved);
    }

    /// @notice See `updateReservedContributors`
    function _updateReservedContributors(IServiceNodeRewards.Contributor[] memory reserved) private {
        require(status == Status.WaitForOperatorContrib, "Contract can not accept new reserved contributors, already received operator contribution");

        // NOTE: Remove old reserved contributions
        {
            uint256 arrayLength = reservedContributionsAddresses.length;
            for (uint256 i = 0; i < arrayLength; i++)
                reservedContributions[reservedContributionsAddresses[i]] = 0;
            delete reservedContributionsAddresses;
        }

        // NOTE: Assign new contributions and verify them
        uint256 remaining = stakingRequirement;

        require(reserved.length <= maxContributors, "Max contributors exceeded in the specified reserved contributors");
        for (uint256 i = 0; i < reserved.length; i++) {
            if (i == 0)
                require(reserved[i].addr == operator,             "The first reservation must be the operator if reserved contributors are given");
            require(reserved[i].addr != address(0),               "Zero address given for contributor");
            require(reservedContributions[reserved[i].addr] == 0, "Duplicate address in reserved contributors");

            // NOTE: Check contribution meets min requirements and running sum
            // doesn't exceed a full stake
            uint256 minContrib     = calcMinimumContribution(remaining, i, maxContributors);
            uint256 contribAmount  = reserved[i].stakedAmount;
            require(contribAmount >= minContrib, "Contribution is below minimum requirement");
            require(remaining >= contribAmount,  "Sum of reserved contribution slots exceeds the staking requirement");
            remaining         -= contribAmount;

            // NOTE: Store the reservation in the contract
            reservedContributionsAddresses.push(reserved[i].addr);
            reservedContributions[reserved[i].addr] = contribAmount;
        }
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
    function contributeFunds(uint256 amount) external { _contributeFunds(msg.sender, amount); }

    /// @notice See `contributeFunds`
    function _contributeFunds(address caller, uint256 amount) private {
        require(status == Status.WaitForOperatorContrib || status == Status.OpenForPublicContrib, "Contract can not accept contributions");

        // NOTE: Check if parent contract invariants changed
        require(maxContributors == stakingRewardsContract.maxContributors(),
                "This contract is outdated and no longer valid because the maximum number of "
                "permitted contributors been changed. Please inform the operator and pre-existing "
                "contributors to exit the contract and re-initiate a new contract.");

        require(stakingRequirement == stakingRewardsContract.stakingRequirement(),
                "This contract is outdated and no longer valid because the staking requirement has "
                "been changed. Please inform the operator to exit the contract and re-initiate a "
                "new contract.");

        // NOTE: Handle operator contribution, initially the operator must contribute to open the
        // contract up to public/reserved contributions.
        if (status == Status.WaitForOperatorContrib) {
            require(caller == operator,
                    "The operator must initially contribute to open the contract for contribution");
            status = Status.OpenForPublicContrib;
            emit OpenForPublicContribution(serviceNodeParams.serviceNodePubkey, operator, serviceNodeParams.fee);
        }

        // NOTE: Verify the contribution
        uint256 reserved = reservedContributions[caller];
        if (reserved > 0) {
            // NOTE: Remove their contribution from the reservation table
            require(amount >= reserved, "Contribution is below the amount reserved for that contributor");
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
            if (contributions[caller] == 0)
                require(amount >= minimumContribution(), "Public contribution is below the minimum allowed");
        }

        // NOTE: Add the contributor to the contract
        if (contributions[caller] == 0)
            contributorAddresses.push(caller);

        // NOTE: Update the amount contributed and transfer the tokens
        contributions[caller]         += amount;
        contributionTimestamp[caller]  = block.timestamp;

        // NOTE: Check contract collateralisation _after_ the amount is
        // committed to the contract to ensure contribution sums are all
        // accounted for.
        require(totalContribution() + totalReservedContribution() <= stakingRequirement, "Contribution exceeds the staking requirement of the contract, rejected");
        require(contributorAddresses.length <= maxContributors, "Maximum number of contributors exceeded");
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
        require(status              == Status.WaitForFinalized, "Contract can not be finalized yet, staking requirement not met or already finalized");
        require(totalContribution() == stakingRequirement,      "Staking requirement has not been met");

        // NOTE: Finalize the contract
        status = Status.Finalized;
        emit Finalized(serviceNodeParams.serviceNodePubkey);

        // NOTE: Setup the contributors for the `stakingRewardsContract`
        IServiceNodeRewards.Contributor[] memory contributors = new IServiceNodeRewards.Contributor[](
            contributorAddresses.length
        );
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            address contributorAddress = contributorAddresses[i];
            contributors[i]            = IServiceNodeRewards.Contributor(contributorAddress, contributions[contributorAddress]);
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
            address[] memory copy = contributorAddresses;
            uint256 length        = copy.length;
            for (uint256 i = 0; i < length; i++)
                removeAndRefundContributor(copy[i]);
            delete contributorAddresses;
        }

        // NOTE: Reset left-over contract variables
        status = Status.WaitForOperatorContrib;

        // NOTE: Remove all reserved contributions
        {
            IServiceNodeRewards.Contributor[] memory zero;
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
    ///   - `contributeFunds`
    ///
    /// If reserved contributors are not desired, an empty array is accepted.
    ///
    /// If the operator wishes to withhold their initial contribution, a `0`
    /// amount is accepted.
    function resetUpdateAndContribute(BN256G1.G1Point memory key,
                                      IServiceNodeRewards.BLSSignatureParams memory sig,
                                      IServiceNodeRewards.ServiceNodeParams memory params,
                                      IServiceNodeRewards.Contributor[] memory reserved,
                                      uint256 amount) external onlyOperator {
        _resetUpdateAndContribute(key, sig, params, reserved, amount);
    }

    /// @notice See `resetUpdateAndContribute`
    function _resetUpdateAndContribute(BN256G1.G1Point memory key,
                                       IServiceNodeRewards.BLSSignatureParams memory sig,
                                       IServiceNodeRewards.ServiceNodeParams memory params,
                                       IServiceNodeRewards.Contributor[] memory reserved,
                                       uint256 amount) private {
        _reset();
        _updatePubkeys(key, sig, params.serviceNodePubkey, params.serviceNodeSignature1, params.serviceNodeSignature2);
        _updateFee(params.fee);
        _updateReservedContributors(reserved);
        if (amount > 0)
            _contributeFunds(operator, amount);
    }

    /// @notice Helper function that updates the fee and contribution of the
    /// node.
    ///
    /// This function is equivalent to calling in sequence:
    ///
    ///   - `reset`
    ///   - `updateFee`
    ///   - `updateReservedContributors`
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
                                                 IServiceNodeRewards.Contributor[] memory reserved,
                                                 uint256 amount) external onlyOperator {
        _reset();
        _updateFee(fee);
        _updateReservedContributors(reserved);
        if (amount > 0)
            _contributeFunds(operator, amount);
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
        require(status == Status.Finalized ||
                status == Status.WaitForOperatorContrib, "Cannot rescue tokens unless contract is finalized or reset");

        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Contract has no balance of the specified token.");

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
        require(
            timeSinceLastContribution >= WITHDRAWAL_DELAY,
            "Withdrawal unavailable: 24 hours have not passed"
        );

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
            if (toRemove == contributorAddresses[index]) {
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
        require(maxNumContributors > numContributors, "Contributors exceed permitted maximum number of contributors");
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
        result = contributorAddresses.length > 0 ? contributions[contributorAddresses[0]] : 0;
        return result;
    }

    /// @notice Access the list of contributor addresses and corresponding contributions.  The
    /// first returned address (if any) is also the operator address.
    function getContributions() public view returns (address[] memory addrs, uint256[] memory contribs) {
        uint256 size = contributorAddresses.length;
        addrs = new address[](size);
        contribs = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            addrs[i] = contributorAddresses[i];
            contribs[i] = contributions[addrs[i]];
        }
        return (addrs, contribs);
    }

    /// @notice Sum up all the contributions recorded in the contributors list
    function totalContribution() public view returns (uint256 result) {
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            address entry = contributorAddresses[i];
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
