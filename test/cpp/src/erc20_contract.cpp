#include "service_node_rewards/erc20_contract.hpp"

#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/utils.hpp"

// Function to call 'approve' method of ERC20 token contract
ethyl::Transaction ERC20Contract::approve(const std::string& spender, uint64_t amount) {
    assert(contractAddress.size());

    ethyl::Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("approve(address,uint256)");

    std::string contractAddressOutput = spender;
    if (contractAddressOutput.substr(0, 2) == "0x")
        contractAddressOutput = contractAddressOutput.substr(2);  // remove "0x"
    // Convert spender address and amount to appropriate format
    std::string spender_padded = ethyl::utils::padTo32Bytes(contractAddressOutput, ethyl::utils::PaddingDirection::LEFT);
    std::string amount_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(amount), ethyl::utils::PaddingDirection::LEFT);


    // Construct the data payload for the transaction
    tx.data = functionSelector + spender_padded + amount_padded;
    return tx;
}

// Function to call 'balanceOf' method of ERC20 token contract
uint64_t ERC20Contract::balanceOf(const std::string& address) {
    assert(contractAddress.size());

    std::string functionSelector = ethyl::utils::toEthFunctionSignature("balanceOf(address)");

    std::string addressOutput = address;
    if (addressOutput.substr(0, 2) == "0x") {
        addressOutput = addressOutput.substr(2);  // remove "0x" prefix if present
    }
    std::string address_padded = ethyl::utils::padTo32Bytes(addressOutput, ethyl::utils::PaddingDirection::LEFT);
    std::string result = provider->callReadFunction(contractAddress, functionSelector + address_padded);

    // Parse the result into a uint64_t
    // Assuming the result is returned as a 32-byte hexadecimal string that fits into uint64_t
    return std::stoull(result.substr(2 + 64 - 8, 8), nullptr, 16);
}

