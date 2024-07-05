#pragma once

#include <memory>
#include <string>

#include "ethyl/provider.hpp"
#include "ethyl/transaction.hpp"

class ERC20Contract {
public:
    // Function to call the 'approve' method of the ERC20 token contract
    ethyl::Transaction approve(const std::string& spender, uint64_t amount);
    uint64_t balanceOf(const std::string& address);

    /// Address of the ERC20 contract that must be set to the address of the
    /// contract on the blockchain for the functions to succeed. If the contract
    /// is not set, the functions that communicate with the provider will send
    /// to the 0 address.
    std::string contractAddress;

    /// Provider must be set with an RPC client configure to allow the contract
    /// to communicate with the blockchain. If the provider is not setup, the
    /// functions that require a provider will throw.
    std::shared_ptr<ethyl::Provider> provider;

};
