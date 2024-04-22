// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../ServiceNodeContribution.sol";

// NOTE: We conduct assertion based testing for the service node contribution
// contract in Echidna. When we use property based-testing, the sender of the
// transactions to `ServiceNodeContribution.sol` is limited to this contract's
// address.
//
// However, `ServiceNodeContribution` is a contract that wants to be tested by
// taking in arbitrary contributions from different wallets. This is possible in
// `assertion` mode instead of `property` mode. This means that tests have to
// enforce invariants using `assert` instead of returning bools.
//
// We've left the `property` based testing in the contract but instead used them
// with asserts to test arbitrary invariants at any point in the contract.

contract ServiceNodeContributionEchidnaTest {

    // TODO: Staking rewards contract address is hard-coded from deployment on devnet
    // TODO: Max contributors is hard-coded
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


    constructor() {
        snOperator     = msg.sender;
        snContribution = new ServiceNodeContribution(
            /*stakingRewardsContract*/ STAKING_REWARDS_CONTRACT,
            /*maxContributors*/        MAX_CONTRIBUTORS,
            /*blsPubkey*/              blsPubkey,
            /*serviceNodeParams*/      snParams);

        sentToken = snContribution.stakingRewardsContract().designatedToken();
    }

    function mintTokensForTesting() internal {
        if (sentToken.allowance(msg.sender, STAKING_REWARDS_CONTRACT) <= 0) {
            sentToken.transferFrom(address(0), msg.sender, type(uint64).max);
            sentToken.approve(address(snContribution), type(uint64).max);
        }
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  Property Testing                        //
    //                                                          //
    //////////////////////////////////////////////////////////////
    function echidna_prop_max_contributor_limit() public view returns (bool) {
        bool result = snContribution.numberContributors() < snContribution.maxContributors();
        assert(result);
        return result;
    }

    function echidna_prop_total_contribution_is_staking_requirement() public view returns (bool) {
        bool result = snContribution.totalContribution() == snContribution.maxContributors() ? (snContribution.totalContribution() == snContribution.stakingRequirement())
                                                                                             : (snContribution.totalContribution() <  snContribution.stakingRequirement());
        assert(result);
        return result;
    }

    function echidna_prop_operator_has_contribution() public view returns (bool) {
        bool result = snContribution.totalContribution() > 0 ? (snContribution.contributions(snContribution.operator()) > 0)
                                                             : (snContribution.contributions(snContribution.operator()) == 0);
        assert(result);
        return result;
    }

    function echidna_prop_check_immutable_props() public view returns (bool) {

        (uint256 serviceNodePubkey,
         uint256 serviceNodeSignature1,
         uint256 serviceNodeSignature2,
         uint16 fee) = snContribution.serviceNodeParams();

        bool snParamsLockedIn = (snParams.serviceNodePubkey     == serviceNodePubkey)     &&
                                (snParams.serviceNodeSignature1 == serviceNodeSignature1) &&
                                (snParams.serviceNodeSignature2 == serviceNodeSignature2) &&
                                (snParams.fee                   == fee);
        assert(snParamsLockedIn);

        (uint256 blsPKeyX, uint256 blsPKeyY) = snContribution.blsPubkey();

        bool result = STAKING_REWARDS_CONTRACT == address(snContribution.stakingRewardsContract())          &&
                      STAKING_REQUIREMENT      == snContribution.stakingRequirement()                       &&
                      MAX_CONTRIBUTORS         == snContribution.maxContributors()                          &&
                      snOperator               == snContribution.operator()                                 &&
                      sentToken                == snContribution.stakingRewardsContract().designatedToken() &&
                      blsPubkey.X              == blsPKeyX                                                  &&
                      blsPubkey.Y              == blsPKeyY                                                  &&
                      snParamsLockedIn;
        assert(result);
        return result;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  Contract Wrapper                        //
    //                                                          //
    //////////////////////////////////////////////////////////////
    function testContributeOperatorFunds(IServiceNodeRewards.BLSSignatureParams memory _blsSignature) public {
        mintTokensForTesting();
        if (snOperator                            == msg.sender &&
            snContribution.operatorContribution() == 0          &&
            !snContribution.cancelled()) {

            uint256 balanceBeforeContribute = sentToken.balanceOf(msg.sender);
            uint256 contribution            = snContribution.minimumContribution();

            assert(snContribution.contributions(snContribution.operator()) == 0);
            assert(snContribution.operatorContribution()                   == 0);
            assert(snContribution.totalContribution()                      == 0);
            assert(snContribution.numberContributors()                     == 0);

            try snContribution.contributeOperatorFunds(_blsSignature) {
            } catch {
                assert(false); // Contribute must succeed as all necessary preconditions are met
            }

            assert(snContribution.contributions(snContribution.operator()) >= snContribution.minimumContribution());
            assert(snContribution.operatorContribution()                   >= snContribution.minimumContribution());
            assert(snContribution.totalContribution()                      >= snContribution.minimumContribution());
            assert(snContribution.numberContributors()                     == 1);

            assert(sentToken.balanceOf(msg.sender) == balanceBeforeContribute - contribution);
        } else {
            try snContribution.contributeOperatorFunds(_blsSignature) {
                assert(false); // Contribute as operator must not succeed
            } catch {
            }
        }

    }

    function testContributeFunds(uint256 amount) public {
        mintTokensForTesting();
        uint256 balanceBeforeContribute = sentToken.balanceOf(msg.sender);

        if (snContribution.totalContribution() < STAKING_REQUIREMENT) {
            try snContribution.contributeFunds(amount) {
            } catch {
                assert(false); // Contribute must not fail as we have tokens and are under the staking requirement
            }
        } else {
            try snContribution.contributeFunds(amount) {
                assert(false); // Contribute must not succeed as we have hit the staking requirement
            } catch {
            }
        }
        assert(snContribution.numberContributors() < snContribution.maxContributors());
        assert(snContribution.totalContribution() <= STAKING_REQUIREMENT);

        assert(sentToken.balanceOf(msg.sender) == balanceBeforeContribute - amount);
    }

    function testFinalizeNode() public {
        if (snContribution.finalized()) {
            try snContribution.finalizeNode() {
                assert(false); // Finalize must fail as we are already finalized
            } catch {
            }
        } else {
            if (snContribution.totalContribution() == STAKING_REQUIREMENT) {
                try snContribution.finalizeNode() {
                } catch {
                    assert(false); // Finalize must succeed if we hit the staking requirement
                }
            } else {
                try snContribution.finalizeNode() {
                    assert(false); // Finalize must always fail because we haven't hit the staking requirement
                } catch {
                }
            }
        }

        if (snContribution.finalized()) {
            assert(snContribution.totalContribution() == STAKING_REQUIREMENT);
        } else {
            assert(snContribution.totalContribution() < STAKING_REQUIREMENT);
        }
    }

    function testWithdrawStake() public {
        uint256 contribution          = snContribution.contributions(msg.sender);
        uint256 balanceBeforeWithdraw = sentToken.balanceOf(msg.sender);

        if (snOperator != msg.sender) {
            snContribution.withdrawStake();
            assert(snContribution.contributions(msg.sender) == 0);
        } else {
            try snContribution.withdrawStake() {
                assert(false); // Not allowed to withdraw since sender hasn't contributed
            } catch {
            }
        }

        assert(!snContribution.finalized());
        assert(snContribution.contributions(msg.sender) == 0);
        assert(snContribution.operatorContribution()    >  0 && snContribution.operatorContribution() <= STAKING_REQUIREMENT);
        assert(snContribution.totalContribution()       >  0 && snContribution.totalContribution()    <= STAKING_REQUIREMENT);
        assert(snContribution.numberContributors()      >  0 && snContribution.numberContributors()   <= MAX_CONTRIBUTORS);

        assert(sentToken.balanceOf(msg.sender) == balanceBeforeWithdraw + contribution);
    }

    function testCancelNode() public {
        uint256 operatorContribution = snContribution.contributions(msg.sender);
        uint256 balanceBeforeCancel  = sentToken.balanceOf(msg.sender);

        if (snContribution.finalized() || snContribution.cancelled()) {
            try snContribution.cancelNode() {
                assert(false); // Can't cancel after finalized or cancelled
            } catch {
            }
        } else {
            if (msg.sender == snOperator) {
                try snContribution.cancelNode() {
                } catch {
                    assert(false); // Can cancel at any point before finalization
                }
                assert(snContribution.cancelled());
                assert(snContribution.contributions(msg.sender) == 0);
            } else {
                try snContribution.cancelNode() {
                    assert(false); // Can never cancel because we are not operator
                } catch {
                }
            }
            assert(!snContribution.finalized());
        }

        assert(sentToken.balanceOf(msg.sender) == balanceBeforeCancel + operatorContribution);
    }

    function testMinimumContribution() public view returns (uint256) {
        uint256 result = snContribution.minimumContribution();
        assert(result <= STAKING_REQUIREMENT);
        return result;
    }

    /*
     * @notice Fuzz all branches of `_minimumContribution`
     */
    function test_MinimumContribution(uint256 _contributionRemaining, uint256 _numberContributors, uint256 _maxContributors) public view returns (uint256) {
        uint256 result = snContribution._minimumContribution(_contributionRemaining,
                                                             _numberContributors,
                                                             _maxContributors);
        return result;
    }

    /*
     * @notice Fuzz the non-reverting branch of `_minimumContribution` by
     * sanitising inputs into the desired ranges.
     */
    function testFiltered_MinimumContribution(uint256 _contributionRemaining, uint256 _numberContributors, uint256 _maxContributors) public view returns (uint256) {
        uint256 maxContributors    = (_maxContributors    % (MAX_CONTRIBUTORS + 1));
        uint256 numberContributors = (_numberContributors % (maxContributors  + 1));
        uint256 result             = snContribution._minimumContribution(_contributionRemaining,
                                                                         numberContributors,
                                                                         maxContributors);
        assert(result <= _contributionRemaining);
        return result;
    }
}
