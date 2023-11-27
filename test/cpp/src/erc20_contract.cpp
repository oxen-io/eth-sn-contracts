#include "service_node_rewards/erc20_contract.hpp"

#include "service_node_rewards/ec_utils.hpp"

// Constructor
ERC20Contract::ERC20Contract(const std::string& _contractAddress, std::shared_ptr<Provider> _provider)
    : contractAddress(_contractAddress), provider(_provider) {}

// Function to call 'approve' method of ERC20 token contract
Transaction ERC20Contract::approve(const std::string& spender, uint64_t amount) {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("approve(address,uint256)");

    std::string contractAddressOutput = spender;
    if (contractAddressOutput.substr(0, 2) == "0x")
        contractAddressOutput = contractAddressOutput.substr(2);  // remove "0x"
    // Convert spender address and amount to appropriate format
    std::string spender_padded = utils::padTo32Bytes(contractAddressOutput, utils::PaddingDirection::LEFT);
    std::string amount_padded = utils::padTo32Bytes(utils::decimalToHex(amount), utils::PaddingDirection::LEFT);


    // Construct the data payload for the transaction
    tx.data = functionSelector + spender_padded + amount_padded;
    return tx;
}

