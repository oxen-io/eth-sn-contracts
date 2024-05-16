#include <iostream>

#include "ethyl/provider.hpp"
#include "ethyl/signer.hpp"
#include "service_node_rewards/config.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

TEST_CASE( "Get balance from local network", "[ethereum]" ) {
    const auto& config = ethbls::get_config(ethbls::network_type::LOCAL);
    ethyl::Provider client;
    client.addClient("Local Client", std::string(config.RPC_URL));

    // Get the balance of the first hardhat address and make sure it has a balance
    auto balance = client.getBalance("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    REQUIRE( balance != "0");
}

TEST_CASE( "Get latest contract address", "[ethereum]" ) {
    const auto& config = ethbls::get_config(ethbls::network_type::LOCAL);
    ethyl::Provider client;
    client.addClient("Local Client", std::string(config.RPC_URL));

    // Get the deployed contract, make sure it exists
    auto contract_address = client.getContractDeployedInLatestBlock();
    REQUIRE(contract_address != "");
}
