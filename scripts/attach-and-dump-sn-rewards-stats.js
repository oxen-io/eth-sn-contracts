const { ethers } = require('hardhat');
async function main() {
    const sn_rewards_factory = await ethers.getContractFactory('TestnetServiceNodeRewards');
    const stagenet           = '0xb691e7C159369475D0a3d4694639ae0144c7bAB2';
    const devnet             = '0x3433798131A72d99C5779E2B4998B17039941F7b';
    const sn_rewards         = await sn_rewards_factory.attach(stagenet);

    const aggregate_pubkey = await sn_rewards.aggregatePubkey();
    console.log("Aggregate Pubkey:                   " + aggregate_pubkey[0].toString(16) + " " + aggregate_pubkey[1].toString(16));
    console.log("BLS Non Signer Threshold Max:       " + await sn_rewards.blsNonSignerThresholdMax());
    console.log("BLS Non Signer Threshold:           " + await sn_rewards.blsNonSignerThreshold());
    console.log("Claim Threshold:                    " + await sn_rewards.claimThreshold());
    console.log("Claim Cycle:                        " + await sn_rewards.claimCycle());
    console.log("Current Claim Total:                " + await sn_rewards.currentClaimTotal());
    console.log("Current Claim Cycle:                " + await sn_rewards.currentClaimCycle());
    console.log("Last Height Pubkey Aggregated:      " + await sn_rewards.lastHeightPubkeyWasAggregated());
    console.log("Liquidator Reward Ratio:            " + await sn_rewards.liquidatorRewardRatio());
    console.log("Max Contributors:                   " + await sn_rewards.maxContributors());
    console.log("Max Permitted Pubkey Aggregations:  " + await sn_rewards.maxPermittedPubkeyAggregations());
    console.log("Next Service Node ID:               " + await sn_rewards.nextServiceNodeID());
    console.log("Num Pubkey Aggregations For Height: " + await sn_rewards.numPubkeyAggregationsForHeight());
    console.log("Pool Share of Liquidation Ratio:    " + await sn_rewards.poolShareOfLiquidationRatio());
    console.log("Recipient Ratio:                    " + await sn_rewards.recipientRatio());
    console.log("Removal Tag:                        " + await sn_rewards.removalTag());
    console.log("Reward Tag:                         " + await sn_rewards.rewardTag());
    console.log("Staking Requirement:                " + await sn_rewards.stakingRequirement());
    console.log("Total Nodes:                        " + await sn_rewards.totalNodes());

    // NOTE: Print all the Session Node IDs via 'allServiceNodeIDs' into a JS structure
    const all_sn_ids       = await sn_rewards.allServiceNodeIDs(); // -> (sn_id[], (bls_x, bls_y)[])
    const sn_id_array      = all_sn_ids[0];
    const bls_pubkey_array = all_sn_ids[1];

    let js_code_bls_key_array = "  const contract_bls_keys = [\n";
    for (let i = 0; i < all_sn_ids[0].length; i++) {
        const sn_id      = sn_id_array[i];
        const bls_x_u256 = bls_pubkey_array[i][0];
        const bls_y_u256 = bls_pubkey_array[i][1];

        js_code_bls_key_array += "    ";
        js_code_bls_key_array += "/*" + i.toString().padStart(4) + "*/ {";
        js_code_bls_key_array += "'id': " + sn_id.toString().padStart(5) + ", ";
        js_code_bls_key_array += "'bls_pubkey': {'x': BigInt('0x" + bls_x_u256.toString(16).padStart(64, '0') + "'), 'y': BigInt('0x" + bls_y_u256.toString(16).padStart(64, '0') + "')}";
        js_code_bls_key_array += "},\n";
    }
    js_code_bls_key_array += "  ];";
    console.log("All Service Node IDs:\n" + js_code_bls_key_array);

    // NOTE: Enumerate all contributors into a hash table
    console.log("Enumerating contributors, this may take awhile ...");
    let contributor_map = new Map(); // (eth_addr -> (total_staked, rewards_balance, rewards_claimed))
    for (let i = 0; i < all_sn_ids[1].length; i++) {
        const sn_id             = sn_id_array[i];
        const sn_info           = await sn_rewards.serviceNodes(sn_id);
        const contributor_array = sn_info[7];

        for (let contributor_index = 0; contributor_index < contributor_array.length; contributor_index++) {
            const contributor   = contributor_array[contributor_index];
            const eth_addr      = contributor[0];
            const staked_amount = contributor[1];

            let total_staked_sum = staked_amount;
            if (contributor_map.has(eth_addr))
                total_staked_sum += contributor_map.get(eth_addr).total_staked

            contributor_map.set(eth_addr,
                {
                    total_staked: total_staked_sum,
                    rewards_balance: 0n,
                    rewards_claimed: 0n
                }
            );
        }
    }

    // NOTE: Enumerate all the rewards
    console.log("Enumerating rewards for " + contributor_map.size + " contributor(s), this may take awhile ...");
    for (let [eth_addr, contributor_info] of contributor_map) {
        const rewards_info = await sn_rewards.recipients(eth_addr); // (balance, claimed)
        contributor_map.set(eth_addr,
            {
                total_staked: contributor_info.total_staked,
                rewards_balance: rewards_info[0],
                rewards_claimed: rewards_info[1],
            }
        );
    }

    // NOTE: Print all active contributor rewards
    let js_code_contributor_rewards = "  const contributor_rewards = [\n";
    for (let [eth_addr, contributor_info] of contributor_map) {
        js_code_contributor_rewards += "    {";
        js_code_contributor_rewards += "'address': " + eth_addr + ", ";
        js_code_contributor_rewards += "'total_staked': " + contributor_info.total_staked + ", ";
        js_code_contributor_rewards += "'rewards_balance': " + contributor_info.rewards_balance + ", ";
        js_code_contributor_rewards += "'rewards_claimed': " + contributor_info.rewards_claimed + ", ";
        js_code_contributor_rewards += "},\n";
    }
    js_code_contributor_rewards += "  ];";
    console.log("Active Contributor Rewards:\n" + js_code_contributor_rewards);

    // TODO: Below is template code for claiming rewards
    /*
    const recipientAddress = '0x3e20171Ee536f616d82094A72cb45D831f3B4449';
    console.log(await sn_rewards.recipients(recipientAddress));
    const totalNodes       = Number(await sn_rewards.totalNodes());
    const recipientRewards = 91720222828n;
    const blsSignature = {
        sigs0: BigInt('0x12a520fb303255787ffb8e6c6ee7efa2457897e45f06131f15b6800c5edc33f9'),
        sigs1: BigInt('0x2cf0376d4c77616f1005432249ff672f0d7649bb8474db6cab5e0ee963e0368b'),
        sigs2: BigInt('0x11f6637a4b5713d398cc6fcf68428c5359c57aa08b0874d02266235b2b35b83a'),
        sigs3: BigInt('0x049f82222409bc503d936b8ba9f4b2f984dc5750ded4f0d78b83ad0b098c1caa'),
    };

    const ids = [
        166
    ];
    console.log("There were " + ids.length + " non signers and " + (totalNodes - ids.length) + " signers (" + totalNodes + " altogether)")
    await sn_rewards.updateRewardsBalance(
        recipientAddress,
        recipientRewards,
        blsSignature,
        ids
    );
    */
}
main();
