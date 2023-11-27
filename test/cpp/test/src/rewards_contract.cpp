#include <iostream>
#include <limits>

#include "ethyl/provider.hpp"
#include "ethyl/signer.hpp"
#include "service_node_rewards/config.hpp"
#include "service_node_rewards/service_node_rewards_contract.hpp"
#include "service_node_rewards/erc20_contract.hpp"
#include "service_node_rewards/service_node_list.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

TEST_CASE( "Rewards Contract", "[ethereum]" ) {
    const auto& config = ethbls::get_config(ethbls::network_type::LOCAL);
    auto provider = std::make_shared<Provider>("Client", std::string(config.RPC_URL));

    std::string contract_address = provider->getContractDeployedInLatestBlock();
    REQUIRE(contract_address != "");

    ServiceNodeRewardsContract rewards_contract(contract_address, provider);
    Signer signer(provider);    
    std::vector<unsigned char> seckey = utils::fromHexString(std::string(config.PRIVATE_KEY));

    // Check rewards contract is responding and set to zero
    REQUIRE(rewards_contract.serviceNodesLength() == 0);

    std::string erc20_address = utils::trimAddress(rewards_contract.designatedToken());
    ERC20Contract erc20_contract(erc20_address, provider);

    // Approve our contract and make sure it was successful
    auto tx = erc20_contract.approve(contract_address, std::numeric_limits<std::uint64_t>::max());;
    auto hash = signer.sendTransaction(tx, seckey);
    REQUIRE(hash != "");
    REQUIRE(provider->transactionSuccessful(hash));
    
    //TODO sean make a snapshot of the smart contract

    SECTION( "Add a public key to the smart contract" ) {
        //TODO sean load the snapshot
        ServiceNodeList snl(1);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address);
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession);
            hash = signer.sendTransaction(tx, seckey);
            REQUIRE(hash != "");
            REQUIRE(provider->transactionSuccessful(hash));
        }

    }
}
