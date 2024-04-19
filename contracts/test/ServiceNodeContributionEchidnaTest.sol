// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../ServiceNodeContribution.sol";

contract ServiceNodeContributionEchidnaTest {

    // TODO: Staking requirement is currently hard-coded to value in script/deploy-local-test.js
    // TODO: Immutable variables in the testing contract causes Echidna 2.2.3 to crash
    address                               public STAKING_REWARDS_CONTRACT = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    uint256                               public STAKING_REQUIREMENT      = 100000000000;
    uint256                               public MAX_CONTRIBUTORS         = 5;

    IERC20                                public sentToken;
    ServiceNodeContribution               public snContribution;
    IServiceNodeRewards.ServiceNodeParams public snParams;
    address                               public snOperator;
    BN256G1.G1Point                       public blsPubkey;


    constructor() public {
        snOperator     = msg.sender;
        snContribution = new ServiceNodeContribution(
            /*stakingRewardsContract*/ STAKING_REWARDS_CONTRACT,
            /*maxContributors*/        MAX_CONTRIBUTORS,
            /*blsPubkey*/              blsPubkey,
            /*serviceNodeParams*/      snParams);

        sentToken = snContribution.stakingRewardsContract().designatedToken();
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  Property Testing                        //
    //                                                          //
    //////////////////////////////////////////////////////////////
    function echidna_prop_max_contributor_limit() public view returns (bool) {
        bool result = snContribution.numberContributors() < snContribution.maxContributors();
        return result;
    }

    function echidna_prop_total_contribution_is_staking_requirement() public view returns (bool) {
        bool result = snContribution.totalContribution() == snContribution.maxContributors() ? (snContribution.totalContribution() == snContribution.stakingRequirement())
                                                                                             : (snContribution.totalContribution() <  snContribution.stakingRequirement());
        return result;
    }

    function echidna_prop_operator_has_contribution() public view returns (bool) {
        bool result = snContribution.totalContribution() > 0 ? (snContribution.contributions(snContribution.operator()) > 0)
                                                             : (snContribution.contributions(snContribution.operator()) == 0);
        return result;
    }

    function echidna_prop_check_immutable_props() public view returns (bool) {
        bool result = STAKING_REWARDS_CONTRACT == address(snContribution.stakingRewardsContract()) &&
                      STAKING_REQUIREMENT      == snContribution.stakingRequirement()              &&
                      MAX_CONTRIBUTORS         == snContribution.maxContributors()                 &&
                      snOperator               == snContribution.operator();
        return result;
    }

    function echidna_prop_service_node_params_are_locked_in() public view returns (bool) {
        (uint256 serviceNodePubkey,
         uint256 serviceNodeSignature1,
         uint256 serviceNodeSignature2,
         uint16 fee) = snContribution.serviceNodeParams();
        bool result = (snParams.serviceNodePubkey     == serviceNodePubkey)     &&
                      (snParams.serviceNodeSignature1 == serviceNodeSignature1) &&
                      (snParams.serviceNodeSignature2 == serviceNodeSignature2) &&
                      (snParams.fee                   == fee);

        return result;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  Contract Wrapper                        //
    //                                                          //
    //////////////////////////////////////////////////////////////
    function testContributeOperatorFunds(IServiceNodeRewards.BLSSignatureParams memory _blsSignature) public {
        snContribution.contributeOperatorFunds(_blsSignature);
    }

    function testContributeFunds(uint256 amount) public {
        if (snContribution.totalContribution() < STAKING_REQUIREMENT) {
            try snContribution.contributeFunds(amount) {
            } catch {
                assert(false);
            }
        } else {
            try snContribution.contributeFunds(amount) {
                assert(false);
            } catch {
            }
        }
        assert(snContribution.numberContributors() < snContribution.maxContributors());
        assert(snContribution.totalContribution() <= STAKING_REQUIREMENT);
    }

    function testFinalizeNode() public {
        if (snContribution.finalized()) {
            try snContribution.finalizeNode() {
                assert(false);
            } catch {
            }
            assert(snContribution.totalContribution() == STAKING_REQUIREMENT);
        } else {
            if (snContribution.totalContribution() == STAKING_REQUIREMENT) {
                try snContribution.finalizeNode() {
                } catch {
                    assert(false);
                }
            } else {
            }
        }
    }

    function testWithdrawStake() public {
        snContribution.withdrawStake();
    }

    function testCancelNode() public {
        snContribution.cancelNode();
    }

    function testMinimumContribution() public view returns (uint256) {
        uint256 result = snContribution.minimumContribution();
        return result;
    }

    function test_MinimumContribution(uint256 _contributionRemaining, uint256 _numberContributors, uint256 _maxContributors) public view returns (uint256) {
        uint256 result = snContribution._minimumContribution(_contributionRemaining,
                                                             _numberContributors,
                                                             _maxContributors);
        return result;
    }
}
