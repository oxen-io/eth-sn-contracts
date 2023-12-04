#pragma once

#include <memory>
#include <string>

#include "ethyl/provider.hpp"
#include "ethyl/transaction.hpp"

class ERC20Contract {
public:
    ERC20Contract(const std::string& contractAddress, std::shared_ptr<Provider> provider);

    // Function to call the 'approve' method of the ERC20 token contract
    Transaction approve(const std::string& spender, uint64_t amount);
    uint64_t balanceOf(const std::string& address);

private:
    std::string contractAddress;
    std::shared_ptr<Provider> provider;
};
