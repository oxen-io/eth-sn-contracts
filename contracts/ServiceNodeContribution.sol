// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./interfaces/IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceNodeContribution {
    using SafeERC20 for IERC20;
    // solhint-disable-next-line var-name-mixedcase
    IERC20 public immutable SENT;
    IServiceNodeRewards public immutable stakingRewardsContract;
    uint256 public immutable stakingRequirement;

    // Service Node Details
    uint256 public immutable serviceNodePubkey;
    address public immutable operator;
    uint256 public immutable feePercentage;
    uint256 public immutable pkX;
    uint256 public immutable pkY;

    // Contributors
    mapping(address => uint256) public contributions;
    uint256 public operatorContribution;
    uint256 public totalContribution;
    uint256 public numberContributors;

    bool public finalized = false;


    modifier onlyOperator() {
        require(tx.origin == operator, "Only the operator can perform this action.");
        _;
    }

    constructor(address _stakingRewardsContract, uint256 _pkX, uint256 _pkY, uint256 _serviceNodePubkey, uint256 _feePercentage) {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        SENT = IERC20(stakingRewardsContract.designatedToken());
        stakingRequirement = stakingRewardsContract.stakingRequirement();
        feePercentage = _feePercentage;
        operator = tx.origin;
        pkX = _pkX;
        pkY = _pkY;
        serviceNodePubkey = _serviceNodePubkey;
    }

    // EVENTS
    event NewContribution(address indexed contributor, uint256 amount);
    event Finalized(uint256 indexed serviceNodePubkey);

    function contributeOperatorFunds() public onlyOperator {
        require (operatorContribution == 0, "Operator already contributed funds");
        operatorContribution = minimumContribution();
        contributeFunds(operatorContribution);
    }

    function contributeFunds(uint256 amount) public {
        require(operatorContribution > 0, "Operator has not contributed funds");
        require(amount >= minimumContribution(), "Contribution is below the minimum requirement.");
        require(totalContribution + amount <= stakingRequirement, "Contribution exceeds the funding goal.");
        contributions[msg.sender] += amount;
        totalContribution += amount;
        numberContributors += 1;
        SENT.safeTransferFrom(msg.sender, address(this), amount);
        emit NewContribution(msg.sender, amount);
    }

    function finalizeNode(uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint256 serviceNodeSignature) public onlyOperator {
        require(totalContribution == stakingRequirement, "Funding goal has not been met.");
        require(!finalized, "Node has already been finalized.");
        finalized = true;
        SENT.approve(address(stakingRewardsContract), stakingRequirement);
        stakingRewardsContract.addBLSPublicKey(pkX, pkY, sigs0, sigs1, sigs2, sigs3, serviceNodePubkey, serviceNodeSignature);
        emit Finalized(serviceNodePubkey);
    }

    function withdrawStake() public {
        require(contributions[msg.sender] > 0, "You have not contributed.");
        require(!finalized, "Node has already been finalized.");
        totalContribution -= contributions[msg.sender];
        contributions[msg.sender] = 0;
        numberContributors -= 1;
        SENT.transfer(msg.sender, contributions[msg.sender]);
    }

    function deleteNode() public onlyOperator {
        require(!finalized, "Cannot delete a finalized node.");
        finalized = true;
        // TODO loop over all contributors send this back to the contributors
        SENT.transfer(msg.sender, contributions[msg.sender]);
    }

    function minimumContribution() public view returns (uint256) {
        //TODO sean roundup
        return stakingRequirement/4;
    }
}

