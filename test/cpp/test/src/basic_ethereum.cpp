#include <iostream>

#include "ethyl/provider.hpp"
#include "ethyl/signer.hpp"
#include "service-node-rewards/config.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

TEST_CASE( "Get balance from local network", "[ethereum]" ) {
    const auto& config = ethbls::get_config(ethbls::network_type::LOCAL);
    Provider client("Local Client", std::string(config.RPC_URL));

    // Get the balance of the first hardhat address
    auto balance = client.getBalance("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    std::cout << __FILE__ << ":" << __LINE__ << " (" << __func__ << ") TODO sean remove this - balance: " << balance << " - debug\n";

    // Check that the balance is greater than zero
    REQUIRE( balance > 0 );
}

