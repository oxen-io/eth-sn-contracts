#include "service_node_rewards/service_node_rewards_contract.hpp"

#include <iostream>

ServiceNodeRewardsContract::ServiceNodeRewardsContract(const std::string& _contractAddress, std::shared_ptr<Provider> _provider)
        : contractAddress(_contractAddress), provider(_provider) {}

Transaction ServiceNodeRewardsContract::addBLSPublicKey(const std::string& publicKey, const std::string& sig) {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("addBLSPublicKey(uint256,uint256,uint256,uint256,uint256,uint256)");
    tx.data = functionSelector + publicKey + sig;
    return tx;
}

uint64_t ServiceNodeRewardsContract::serviceNodesLength() {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    callData.data = utils::getFunctionSignature("serviceNodesLength()");
    std::string result = provider->callReadFunction(callData);
    return utils::fromHexStringToUint64(result);
}

std::string ServiceNodeRewardsContract::designatedToken() {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    callData.data = utils::getFunctionSignature("designatedToken()");
    return provider->callReadFunction(callData);
}

std::string ServiceNodeRewardsContract::aggregatePubkey() {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    callData.data = utils::getFunctionSignature("aggregate_pubkey()");
    return provider->callReadFunction(callData);
}

Transaction ServiceNodeRewardsContract::liquidateBLSPublicKeyWithSignature(const uint64_t service_node_id, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("liquidateBLSPublicKeyWithSignature(uint64,uint256,uint256,uint256,uint256,uint64[])");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    std::string indices_padded = utils::padTo32Bytes("c0", utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(non_signer_indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(index), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + node_id_padded + sig + indices_padded;

    return tx;
}

Transaction ServiceNodeRewardsContract::removeBLSPublicKeyWithSignature(const uint64_t service_node_id, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("removeBLSPublicKeyWithSignature(uint64,uint256,uint256,uint256,uint256,uint64[])");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    std::string indices_padded = utils::padTo32Bytes("c0", utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(non_signer_indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(index), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + node_id_padded + sig + indices_padded;

    return tx;
}

Transaction ServiceNodeRewardsContract::initiateRemoveBLSPublicKey(const uint64_t service_node_id) {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("initiateRemoveBLSPublicKey(uint64)");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    tx.data = functionSelector + node_id_padded;
    return tx;
}

Transaction ServiceNodeRewardsContract::removeBLSPublicKeyAfterWaitTime(const uint64_t service_node_id) {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("removeBLSPublicKeyAfterWaitTime(uint64)");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    tx.data = functionSelector + node_id_padded;
    return tx;
}

//TODO sean review this function
Transaction ServiceNodeRewardsContract::checkSigAGG(const std::string& sig, const std::string& message) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("checkSigAGG(uint256,uint256,uint256,uint256,uint256)");
    std::string message_padded = utils::padTo32Bytes(utils::toHexString(utils::HashModulus(message)), utils::PaddingDirection::LEFT);
    tx.data = functionSelector + sig + message_padded;
    return tx;
}

//TODO sean review this function
Transaction ServiceNodeRewardsContract::checkAggPubkey(const std::string& aggPubkey) {
    Transaction tx(contractAddress, 0, 800000);
    std::string functionSelector = utils::getFunctionSignature("checkAggPubkey(uint256,uint256)");
    tx.data = functionSelector + aggPubkey;
    return tx;
}

//TODO sean review this function
Transaction ServiceNodeRewardsContract::checkSigAGGIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& indices) {
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

//TODO sean review this function
Transaction ServiceNodeRewardsContract::checkSigAGGNegateIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& non_signer_indices) {
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
