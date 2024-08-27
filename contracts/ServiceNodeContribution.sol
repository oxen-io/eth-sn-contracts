// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./libraries/Shared.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Service Node Contribution Contract
 *
 * @dev This contract allows for the collection of contributions towards
 * a service node. Operators usually generate one of these smart contracts using
 * the parent factory contract `ServiceNodeContributionFactory` for each service
 * node they start and wish to collateralise with funds from the public.
 *
 * Contributors can fund the service node until the staking requirement is met.
 * Once the staking requirement is met, the contract is automatically finalized
 * and send the service node registration `ServiceNodeRewards` contract.
 *
 * This contract supports revoking of the contract prior to finalisation,
 * refunding the contribution to the contributors and the operator.
 */
contract ServiceNodeContribution is Shared {
    using SafeERC20 for IERC20;

    // Staking
    // solhint-disable-next-line var-name-mixedcase
    IERC20 public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;
    uint256 public immutable stakingRequirement;

    // Service Node
    BN256G1.G1Point public blsPubkey;
    IServiceNodeRewards.ServiceNodeParams public serviceNodeParams;
    IServiceNodeRewards.BLSSignatureParams public blsSignature;

    // Contributions
    address public immutable operator;
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public contributionTimestamp;
    address[] public contributorAddresses;
    uint256 public immutable maxContributors;

    // Smart Contract
    bool public finalized = false;
    bool public cancelled = false;

    uint64 public constant WITHDRAWAL_DELAY = 1 days;

    // MODIFIERS
    modifier onlyOperator() {
        require(msg.sender == operator, "Only the operator can perform this action.");
        _;
    }

    // EVENTS
    event Cancelled(uint256 indexed serviceNodePubkey);
    event Finalized(uint256 indexed serviceNodePubkey);
    event NewContribution(address indexed contributor, uint256 amount);
    event WithdrawContribution(address indexed contributor, uint256 amount);

    /**
     * @notice Constructs a multi-contribution service node contract for the
     * specified `_stakingRewardsContract`.
     *
     * @dev This contract should typically be invoked from the parent
     * contribution factory `ServiceNodeContributionFactory`.
     *
     * @param _stakingRewardsContract Address of the staking rewards contract.
     * @param _maxContributors Maximum number of contributors allowed.
     * @param _blsPubkey 64 byte BLS public key for the service node.
     * @param _serviceNodeParams Service node public key and signature proving
     * ownership of the public key and the fee the operator is charging.
     */
    constructor(
        address _stakingRewardsContract,
        uint256 _maxContributors,
        BN256G1.G1Point memory _blsPubkey,
        IServiceNodeRewards.ServiceNodeParams memory _serviceNodeParams
    ) nzAddr(_stakingRewardsContract) nzUint(_maxContributors) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        stakingRequirement = stakingRewardsContract.stakingRequirement();
        SENT = IERC20(stakingRewardsContract.designatedToken());

        maxContributors = _maxContributors;
        operator = tx.origin; // NOTE: Creation is delegated by operator through factory
        blsPubkey = _blsPubkey;
        serviceNodeParams = _serviceNodeParams;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Allows the operator to contribute funds towards their own node.
     *
     * It can only be called once by the operator and must be done before any
     * other contributions are made.
     *
     * @dev This function sets the operator's contribution and emits
     * a NewContribution event.
     *
     * @param amount The number of SENT tokens contributed by the operator. It
     * must be at least `minimumContribution` amount of tokens or the operation
     * is reverted.
     * @param _blsSignature 128 byte BLS proof of possession signature that
     * proves ownership of the `blsPubkey`.
     */
    function contributeOperatorFunds(
        uint256 amount,
        IServiceNodeRewards.BLSSignatureParams memory _blsSignature
    ) public onlyOperator {
        require(contributorAddresses.length == 0, "Operator already contributed funds");
        require(!cancelled, "Node has been cancelled.");
        require(amount >= minimumContribution(), "Contribution is below minimum requirement");
        blsSignature = _blsSignature;
        contributeFunds(amount);
    }

    /**
     * @notice Contribute funds to the contract for the service node run by
     * `operator`. The `amount` of SENT token must be at least the
     * `minimumContribution` or otherwise the contribution is reverted.
     *
     * @dev Main entry point for funds to enter the contract. Contributions are
     * only permitted the public if the operator has already contributed and the
     * node has not been finalized or cancelled.
     *
     * @param amount The amount of SENT token to contribute to the contract.
     */
    function contributeFunds(uint256 amount) public {
        // NOTE: Check if we are allowed to call contribute funds
        if (msg.sender == operator) {
            require(
                blsSignatureIsInit(blsSignature),
                "Operator must initially contribute via `contributOperatorFunds`"
            );
        } else {
            // NOTE: Operator must have contributed first before the public can contribute
            require(contributorAddresses.length > 0, "Operator has not contributed funds");
        }

        // NOTE: Check if parent contract invariants changed
        require(maxContributors == stakingRewardsContract.maxContributors(),
                "This contract is outdated and no longer valid because the maximum number of "
                "permitted contributors been changed. Please inform the operator and pre-existing "
                "contributors to cancel the contract, withdraw their funds and to re-initiate a "
                "new contract.");

        require(stakingRequirement == stakingRewardsContract.stakingRequirement(),
                "This contract is outdated and no longer valid because the staking requirement has "
                "been changed. Please inform the operator and pre-existing contributors to cancel "
                "the contract, withdraw their funds and to re-initiate a new contract.");

        // NOTE: Check contract status and collateral
        require(amount >= minimumContribution(), "Contribution is below the minimum requirement.");
        require(totalContribution() + amount <= stakingRequirement, "Contribution exceeds the funding goal.");
        require(!finalized, "Node has already been finalized.");
        require(!cancelled, "Node has been cancelled.");

        // NOTE: Add the contributor to the contract
        if (contributions[msg.sender] == 0) {
            contributorAddresses.push(msg.sender);
        }

        // NOTE: Update the amount contributed and transfer the tokens
        contributions[msg.sender] += amount;
        contributionTimestamp[msg.sender] = block.timestamp;
        emit NewContribution(msg.sender, amount);

        SENT.safeTransferFrom(msg.sender, address(this), amount);

        // NOTE: Finalize the node if the staking requirement is met
        if (totalContribution() == stakingRequirement) {
            finalizeNode();
        }
    }

    /**
     * @notice Invoked when the `totalContribution` of the contract matches the
     * `stakingRequirement`. The service node registration and SENT tokens are
     * transferred to the `stakingRewardsContract` to be included as a service
     * node in the network.
     */
    function finalizeNode() internal {
        require(totalContribution() == stakingRequirement, "Funding goal has not been met.");

        // NOTE: Finalise the contract and setup the contributors for the
        // `stakingRewardsContract`
        finalized = true;
        emit Finalized(serviceNodeParams.serviceNodePubkey);

        IServiceNodeRewards.Contributor[] memory contributors = new IServiceNodeRewards.Contributor[](
            contributorAddresses.length
        );
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            address contributorAddress = contributorAddresses[i];
            contributors[i] = IServiceNodeRewards.Contributor(contributorAddress, contributions[contributorAddress]);
        }

        // NOTE: Transfer SENT and register the service node to the
        // `stakingRewardsContract`
        SENT.approve(address(stakingRewardsContract), stakingRequirement);
        stakingRewardsContract.addBLSPublicKey(blsPubkey, blsSignature, serviceNodeParams, contributors);
    }

    /**
     * @notice Reset the contract allowing it to be reused to re-register the
     * pre-existing node. The service node must be removed from the rewards
     * contract before a contract that has been reset can be refinalized.
     *
     * @dev Since this contract can only be called after finalisation, the SENT
     * balance of this contract will have been transferred to the rewards
     * contract and hence no refunding of balances is necessary.
     *
     * Once finalised, any refunding that has to occur will need to be done via
     * the rewards contract.
     *
     * @param amount The amount of funds the operator is to contribute. This
     * amount must be greater than the minimum operator contribution which can
     * be calculated by calling `calcMinimumContribution` with the staking
     * requirement and 0 contributors.
     */
    function resetContract(uint256 amount) external onlyOperator {
        require(finalized, "You cannot reset a contract that hasn't been finalised yet");

        // NOTE: Zero out all addresses in `contributions`
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            address toRemove = contributorAddresses[i];
            contributions[toRemove] = 0;
        }

        // NOTE: Reset left-over contract variables
        delete contributorAddresses;

        // NOTE: Re-init the contract with the operator contribution.
        finalized = false;
        contributeOperatorFunds(amount, blsSignature);
    }

    /**
     * @notice Allows the operator to update the serviceNodeParams.
     * @dev This function can only be called by the operator, before the contract is finalized,
     * and when there are no other contributors besides the operator.
     * @param newParams The new ServiceNodeParams to set.
     */
    function updateServiceNodeParams(IServiceNodeRewards.ServiceNodeParams memory newParams) public onlyOperator {
        require(!finalized, "Cannot update params: Node has already been finalized.");
        require(contributorAddresses.length == 1, "Cannot update params: Other contributors have already joined.");

        serviceNodeParams = newParams;
    }

    /**
     * @notice Allows the operator to update the blsPubkey.
     * @dev This function can only be called by the operator, before the contract is finalized,
     * and when there are no other contributors besides the operator.
     * @param newBlsPubkey The new BLS Pubkey to set.
     */
    function updateBLSPubkey(BN256G1.G1Point memory newBlsPubkey) public onlyOperator {
        require(!finalized, "Cannot update pubkey: Node has already been finalized.");
        require(contributorAddresses.length == 1, "Cannot update pubkey: Other contributors have already joined.");

        blsPubkey = newBlsPubkey;
    }

    /**
     * @notice Function to allow owner to rescue any ERC20 tokens sent to the
     * contract after it has been finalized.
     *
     * @dev Rescue is only allowed after finalisation so any token balance from
     * contributors have been transferred to the `stakingRewardsContract` and
     * the remaining tokens are those sent mistakenly after finalisation.
     *
     * @param tokenAddress The ERC20 token to rescue from the contract.
     */
    function rescueERC20(address tokenAddress) external onlyOperator {
        require(finalized, "Contract has not been finalized yet.");
        require(!cancelled, "Contract has been cancelled.");

        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Contract has no balance of the specified token.");

        token.safeTransfer(operator, balance);
    }

    /**
     * @notice Allows contributors to withdraw their individual contribution if
     * the contract has not been finalized.

     * After finalization, the registration is transferred to the
     * `stakingRewardsContract` and withdrawal by or the operator contributors
     * must be done through that contract.
     */
    function withdrawContribution() public {
        require(contributions[msg.sender] > 0, "You have not contributed.");
        require(!finalized, "Node has already been finalized.");
        require(msg.sender != operator, "Operator cannot withdraw");

        // NOTE: We permit a withdraw if the contract has been cancelled (as the
        // contract is killed and can no-longer be interacted with except
        // removal of funds), a withdrawal delay is no longer required.
        if (!cancelled) {
            require(
                block.timestamp - contributionTimestamp[msg.sender] > WITHDRAWAL_DELAY,
                "Withdrawal unavailable: 24 hours have not passed"
            );
        }

        uint256 refundAmount = removeAndRefundContributor(msg.sender);
        emit WithdrawContribution(msg.sender, refundAmount);
    }

    /**
     * @notice Cancels the service node contract. The contract will refund the
     * operator and contributors are able to invoke `withdrawContribution` to
     * return their contributions.
     *
     * @dev This can only be done by the operator and only if the node has not
     * been finalized or already has already called cancelled.
     */
    function cancelNode() public onlyOperator {
        require(!finalized, "Cannot cancel a finalized node.");
        require(!cancelled, "Node has already been cancelled.");
        cancelled = true;
        uint256 arrayLength = contributorAddresses.length;
        address[] memory _contributorAddresses = contributorAddresses;
        for (uint256 i = 0; i < arrayLength; i++) {
            address entry = _contributorAddresses[i];
            removeAndRefundContributor(entry);
        }
        emit Cancelled(serviceNodeParams.serviceNodePubkey);
    }

    /**
     * @dev Remove the contributor by address specified by `toRemove` from the
     * smart contract. This updates all contributor related smart contract
     * variables including the:
     *
     *   1) Removing contributor from contribution mapping
     *   2) Removing their address from the contribution array
     *   3) Refunding the SENT amount contributed to the contributor
     *
     * @return result The amount of SENT refunded for the given `toRemove`
     * address. If `toRemove` is not a contributor/does not exist, 0 is returned
     * as the refunded amount.
     */
    function removeAndRefundContributor(address toRemove) private returns (uint256 result) {
        result = contributions[toRemove];
        if (result == 0) return result;

        // 1) Removing contributor from contribution mapping
        contributions[toRemove] = 0;

        // 2) Removing their address from the contribution array
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 index = 0; index < arrayLength; index++) {
            if (toRemove == contributorAddresses[index]) {
                contributorAddresses[index] = contributorAddresses[arrayLength - 1];
                contributorAddresses.pop();
                break;
            }
        }

        // 3) Refunding the SENT amount contributed to the contributor
        SENT.safeTransfer(toRemove, result);
        return result;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Checks if the BLS signature has been set to non-zero values.
     * @dev This is used to guard against the operator calling `contributeFunds`
     * directly before calling `contributeOperatorFunds` otherwise an operator
     * could fund a node without setting the BLS proof-of-possession signature.
     */
    function blsSignatureIsInit(
        IServiceNodeRewards.BLSSignatureParams memory params
    ) private pure returns (bool result) {
        result = params.sigs0 > 0 || params.sigs1 > 0 || params.sigs2 > 0 || params.sigs3 > 0;
        return result;
    }

    /**
     * @notice Calculates the minimum contribution amount given the current
     * contribution status of the contract.
     *
     * @dev The minimum contribution is dynamically calculated based on the
     * number of contributors and the staking requirement. It returns
     * math.ceilDiv of the calculation
     *
     * @return result The minimum contribution amount.
     */
    function minimumContribution() public view returns (uint256 result) {
        result = calcMinimumContribution(
            stakingRequirement - totalContribution(),
            contributorAddresses.length,
            maxContributors
        );
        return result;
    }

    /**
     * @notice Function to calculate the minimum contribution given the staking
     * parameters.
     *
     * This function reverts if invalid parameters are given such that the
     * operations would wrap or divide by 0.
     *
     * @param contributionRemaining The amount of contribution still available
     * to be contributed to this contract.
     * @param numContributors The number of contributors that have contributed
     * to the contract already including the operator.
     * @param maxNumContributors The maximum number of contributors allowed to
     * contribute to this contract.
     */
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

    /**
     * @notice Calculates the minimum operator contribution given the staking
     * requirement.
     */
    function minimumOperatorContribution(uint256 _stakingRequirement) public pure returns (uint256 result) {
        result = calcMinimumContribution(_stakingRequirement, 0, 1);
        return result;
    }

    /**
     * @dev This function allows unit-tests to query the length without having
     * to know the storage slot of the array size.
     */
    function contributorAddressesLength() public view returns (uint256 result) {
        result = contributorAddresses.length;
        return result;
    }

    /**
     * @notice Get the contribution by the operator, defined to always be the
     * first contribution in the contract.
     */
    function operatorContribution() public view returns (uint256 result) {
        result = contributorAddresses.length > 0 ? contributions[contributorAddresses[0]] : 0;
        return result;
    }

    /**
     * @notice Sum up all the contributions recorded in the contributors list
     */
    function totalContribution() public view returns (uint256 result) {
        uint256 arrayLength = contributorAddresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            address entry = contributorAddresses[i];
            result += contributions[entry];
        }
        return result;
    }
}
