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

Recipient ServiceNodeRewardsContract::viewRecipientData(const std::string& address) {
    ReadCallData callData;
    callData.contractAddress = contractAddress;

    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    rewardAddressOutput = utils::padTo32Bytes(rewardAddressOutput, utils::PaddingDirection::LEFT);
    callData.data = utils::getFunctionSignature("recipients(address)") + rewardAddressOutput;

    std::string result = provider->callReadFunction(callData);

    // This assumes both the returned integers fit into a uint64_t but they are actually uint256 and dont have a good way of storing the 
    // full amount. In tests this will just mean that we need to keep our numbers below the 64bit max.
    std::string rewardsHex = result.substr(2 + 64-8, 8);
    std::string claimedHex = result.substr(2 + 64 + 64-8, 8);

    uint64_t rewards = std::stoull(rewardsHex, nullptr, 16);
    uint64_t claimed = std::stoull(claimedHex, nullptr, 16);

    return Recipient(rewards, claimed);
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

Transaction ServiceNodeRewardsContract::updateRewardsBalance(const std::string& address, const uint64_t amount, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("updateRewardsBalance(address,uint256,uint256,uint256,uint256,uint256,uint64[])");
    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    rewardAddressOutput = utils::padTo32Bytes(rewardAddressOutput, utils::PaddingDirection::LEFT);
    std::string amount_padded = utils::padTo32Bytes(utils::decimalToHex(amount), utils::PaddingDirection::LEFT);
    std::string indices_padded = utils::padTo32Bytes("e0", utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(non_signer_indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(index), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + rewardAddressOutput + amount_padded + sig + indices_padded;

    return tx;
}

Transaction ServiceNodeRewardsContract::claimRewards() {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("claimRewards()");
    tx.data = functionSelector;
    return tx;
}
