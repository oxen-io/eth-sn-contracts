#include "eth-bls/bls_validator_contract.hpp"
#include "eth-bls/utils.hpp"
#include "eth-bls/ec_utils.hpp"

#include <iostream>

BLSValidatorsContract::BLSValidatorsContract(const std::string& _contractAddress, std::shared_ptr<Provider> _provider)
        : contractAddress(_contractAddress), provider(_provider) {}

Transaction BLSValidatorsContract::addValidator(const std::string& publicKey) {
    const uint64_t amount = 15000;
    Transaction tx(contractAddress, 0, 300000);

    std::string functionSelector = utils::getFunctionSignature("addValidator(uint256,uint256,uint256)");

    // Convert amount to hex string and pad it to 32 bytes
    std::string amount_padded = utils::padTo32Bytes(utils::decimalToHex(amount), utils::PaddingDirection::LEFT);

    // Concatenate the function selector and the encoded arguments
    tx.data = functionSelector + publicKey + amount_padded;

    return tx;
}

Transaction BLSValidatorsContract::clear(uint64_t additional_gas) {
    Transaction tx(contractAddress, 0, 30000000 + additional_gas);
    tx.data = utils::getFunctionSignature("clearValidators()");
    return tx;
}

uint64_t BLSValidatorsContract::getValidatorsLength() {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    callData.data = utils::getFunctionSignature("getValidatorsLength()");
    std::string result = provider->callReadFunction(callData);
    return utils::fromHexStringToUint64(result);
}

Transaction BLSValidatorsContract::checkSigAGG(const std::string& sig, const std::string& message) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("checkSigAGG(uint256,uint256,uint256,uint256,uint256)");
    std::string message_padded = utils::padTo32Bytes(utils::toHexString(utils::HashModulus(message)), utils::PaddingDirection::LEFT);
    tx.data = functionSelector + sig + message_padded;
    return tx;
}

Transaction BLSValidatorsContract::checkAggPubkey(const std::string& aggPubkey) {
    Transaction tx(contractAddress, 0, 800000);
    std::string functionSelector = utils::getFunctionSignature("checkAggPubkey(uint256,uint256)");
    tx.data = functionSelector + aggPubkey;
    return tx;
}

Transaction BLSValidatorsContract::checkSigAGGIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& indices) {
    Transaction tx(contractAddress, 0, 30000000);
    //std::string functionSelector = utils::getFunctionSignature("checkSigAGGIndices(uint256[4],uint256,uint256[])");
    std::string functionSelector = utils::getFunctionSignature("checkSigAGGIndices(uint256,uint256,uint256,uint256,uint256,uint256[])");
    std::string message_padded = utils::padTo32Bytes(utils::toHexString(utils::HashModulus(message)), utils::PaddingDirection::LEFT);
    // TODO sean this c0 is a RLP encoding thing, should abstract the "encode a list" to somewhere else
    std::string indices_padded = utils::padTo32Bytes("c0", utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(static_cast<uint64_t>(index)), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + sig + message_padded + indices_padded;

    return tx;
}

Transaction BLSValidatorsContract::checkSigAGGNegateIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& non_signer_indices) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("checkSigAGGNegateIndices(uint256,uint256,uint256,uint256,uint256,uint256[])");
    std::string message_padded = utils::padTo32Bytes(utils::toHexString(utils::HashModulus(message)), utils::PaddingDirection::LEFT);
    // TODO sean this c0 is a RLP encoding thing, should abstract the "encode a list" to somewhere else
    std::string indices_padded = utils::padTo32Bytes("c0", utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(non_signer_indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(static_cast<uint64_t>(index)), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + sig + message_padded + indices_padded;

    return tx;
}

Transaction BLSValidatorsContract::validateProofOfPossession(const std::string& publicKey, const std::string& sig) {
    Transaction tx(contractAddress, 0, 1500000);
    std::string functionSelector = utils::getFunctionSignature("validateProofOfPossession(uint256,uint256,uint256,uint256,uint256,uint256)");
    tx.data = functionSelector + publicKey + sig;
    return tx;
}

std::string BLSValidatorsContract::calcField(const std::string& publicKey) {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    std::string functionSelector = utils::getFunctionSignature("calcField(uint256,uint256)");
    callData.data = functionSelector + publicKey;
    return provider->callReadFunction(callData);
}
