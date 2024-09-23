#include "service_node_rewards/service_node_rewards_contract.hpp"
#include "ethyl/utils.hpp"
#include <nlohmann/json.hpp>

ethyl::Transaction ServiceNodeRewardsContract::addBLSPublicKey(const std::string& publicKey, const std::string& sig, const std::string& serviceNodePubkey, const std::string& serviceNodeSignature, const uint64_t fee) {
    ethyl::Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("addBLSPublicKey((uint256,uint256),(uint256,uint256,uint256,uint256),(uint256,uint256,uint256,uint16),(address,uint256)[])");

    const std::string serviceNodePubkeyPadded = ethyl::utils::padTo32Bytes(oxenc::to_hex(serviceNodePubkey), ethyl::utils::PaddingDirection::LEFT);
    const std::string serviceNodeSignaturePadded = ethyl::utils::padToNBytes(oxenc::to_hex(serviceNodeSignature), 64, ethyl::utils::PaddingDirection::LEFT);
    const std::string fee_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(fee), ethyl::utils::PaddingDirection::LEFT);

    // 11 parameters before the contributors array
    const std::string contributors_offset = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(11 * 32), ethyl::utils::PaddingDirection::LEFT);
    // empty for now
    const std::string contributors = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(0), ethyl::utils::PaddingDirection::LEFT);

    tx.data = functionSelector + publicKey + sig + serviceNodePubkeyPadded + serviceNodeSignaturePadded + fee_padded + contributors_offset + contributors;

    return tx;
}

ContractServiceNode ServiceNodeRewardsContract::serviceNodes(uint64_t index)
{
    nlohmann::json callResult;
    try {
        std::string  indexABI            = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(index), ethyl::utils::PaddingDirection::LEFT);
        auto data                        = ethyl::utils::toEthFunctionSignature("serviceNodes(uint64)") + indexABI;
        callResult                       = provider.callReadFunctionJSON(contractAddress, data);
        const std::string& callResultHex = callResult.get_ref<nlohmann::json::string_t&>();
        std::string_view   callResultIt  = ethyl::utils::trimPrefix(callResultHex, "0x");

        const size_t        U256_HEX_SIZE                  = (256 / 8) * 2;
        const size_t        BLS_PKEY_XY_COMPONENT_HEX_SIZE = 32 * 2;
        const size_t        BLS_PKEY_HEX_SIZE              = BLS_PKEY_XY_COMPONENT_HEX_SIZE + BLS_PKEY_XY_COMPONENT_HEX_SIZE;
        const size_t        ADDRESS_HEX_SIZE               = 32 * 2;
        const size_t        ETH_ADDRESS_HEX_SIZE           = 20 * 2;

        ContractServiceNode result                   = {};
        size_t              walkIt                   = 0;
        std::string_view    initialElementOffset     = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += initialElementOffset.size();
        std::string_view    nextHex                  = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += nextHex.size();
        std::string_view    prevHex                  = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += prevHex.size();
        std::string_view    operatorAddressHex       = callResultIt.substr(walkIt, ADDRESS_HEX_SIZE);  walkIt += operatorAddressHex.size();
        std::string_view    pubkeyHex                = callResultIt.substr(walkIt, BLS_PKEY_HEX_SIZE); walkIt += pubkeyHex.size();
        std::string_view    addedTimestampHex        = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += addedTimestampHex.size();
        std::string_view    leaveRequestTimestampHex = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += leaveRequestTimestampHex.size();
        std::string_view    depositHex               = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += depositHex.size();
        std::string_view    weirdOffsetHex           = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += weirdOffsetHex.size();
        std::string_view    contributorCountHex      = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += contributorCountHex.size();

        // NOTE: Deserialize linked list
        result.next                = ethyl::utils::hexStringToU64(nextHex);
        result.prev                = ethyl::utils::hexStringToU64(prevHex);

        // only need to fill in next and prev for sentinel, and probably not even those
        if (index == 0) return result;

        size_t contributor_count = ethyl::utils::hexStringToU64(contributorCountHex);
        for (size_t i=0; i < contributor_count; i++) {
            Contributor c;
            std::string_view contributorAddressHex = callResultIt.substr(walkIt, ADDRESS_HEX_SIZE);    walkIt += contributorAddressHex.size();
            std::string_view contributorAmountHex  = callResultIt.substr(walkIt, U256_HEX_SIZE);       walkIt += contributorAmountHex.size();

            std::vector<unsigned char> addressBytes = ethyl::utils::fromHexString(contributorAddressHex.substr(contributorAddressHex.size() - ETH_ADDRESS_HEX_SIZE, ETH_ADDRESS_HEX_SIZE));
            assert(addressBytes.size() == sizeof(Contributor::address));
            std::memcpy(c.address.data(), addressBytes.data(), addressBytes.size());

            c.amount = ethyl::utils::hexStringToU64(contributorAmountHex);
            result.contributors.push_back(std::move(c));
        }
        assert(walkIt == callResultIt.size());

        // NOTE: Deserialise recipient
        std::vector<unsigned char> recipientBytes = ethyl::utils::fromHexString(operatorAddressHex.substr(operatorAddressHex.size() - ETH_ADDRESS_HEX_SIZE, ETH_ADDRESS_HEX_SIZE));
        assert(recipientBytes.size() == result.recipient.max_size());
        std::memcpy(result.recipient.data(), recipientBytes.data(), recipientBytes.size());

        // NOTE: Deserialise key hex into BLS key
        result.pubkey = utils::HexToBLSPublicKey(pubkeyHex);

        // NOTE: Deserialise metadata
        result.addedTimestamp = ethyl::utils::hexStringToU64(addedTimestampHex);
        result.leaveRequestTimestamp = ethyl::utils::hexStringToU64(leaveRequestTimestampHex);
        result.deposit               = depositHex;
        return result;
    } catch (const std::exception& e) {
        throw std::runtime_error{std::string("response: ") + callResult.dump()};
    }
}

uint64_t ServiceNodeRewardsContract::serviceNodeIDs(const bls::PublicKey& pKey)
{
    // NOTE: Generate the ABI caller data
    std::string pKeyABI             = utils::BLSPublicKeyToHex(pKey);
    std::string methodABI           = ethyl::utils::toEthFunctionSignature("serviceNodeIDs(bytes)");
    std::string offsetToPKeyDataABI = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(32) /*offset includes the 32 byte offset itself*/, ethyl::utils::PaddingDirection::LEFT);
    std::string bytesSizeABI        = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(pKeyABI.size() / 2), ethyl::utils::PaddingDirection::LEFT);

    // NOTE: Setup call data

    // NOTE: Fill in ABI
    std::string data{};
    data.reserve(methodABI.size() + offsetToPKeyDataABI.size() + bytesSizeABI.size() + pKeyABI.size());
    data += methodABI;
    data += offsetToPKeyDataABI;
    data += bytesSizeABI;
    data += pKeyABI;

    // NOTE: Call function
    nlohmann::json     callResult = provider.callReadFunctionJSON(contractAddress, data);
    const std::string& resultHex  = callResult.get_ref<nlohmann::json::string_t&>();
    uint64_t           result     = ethyl::utils::hexStringToU64(resultHex);
    return result;
}

uint64_t ServiceNodeRewardsContract::serviceNodesLength() {
    auto data = ethyl::utils::toEthFunctionSignature("serviceNodesLength()");
    std::string result = provider.callReadFunction(contractAddress, data);
    return ethyl::utils::hexStringToU64(result);
}

uint64_t ServiceNodeRewardsContract::maxPermittedPubkeyAggregations() {
    auto data = ethyl::utils::toEthFunctionSignature("maxPermittedPubkeyAggregations()");
    std::string result = provider.callReadFunction(contractAddress, data);
    return ethyl::utils::hexStringToU64(result);
}

std::string ServiceNodeRewardsContract::designatedToken() {
    auto data = ethyl::utils::toEthFunctionSignature("designatedToken()");
    return provider.callReadFunction(contractAddress, data);
}

std::string ServiceNodeRewardsContract::aggregatePubkeyString() {
    auto data            = ethyl::utils::toEthFunctionSignature("aggregatePubkey()");
    return provider.callReadFunction(contractAddress, data);
}

bls::PublicKey ServiceNodeRewardsContract::aggregatePubkey() {
    std::string    hex    = ServiceNodeRewardsContract::aggregatePubkeyString();
    bls::PublicKey result = utils::HexToBLSPublicKey(hex);
    return result;
}

Recipient ServiceNodeRewardsContract::viewRecipientData(const std::string& address) {
    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    rewardAddressOutput = ethyl::utils::padTo32Bytes(rewardAddressOutput, ethyl::utils::PaddingDirection::LEFT);
    auto data = ethyl::utils::toEthFunctionSignature("recipients(address)") + rewardAddressOutput;

    std::string result = provider.callReadFunction(contractAddress, data);

    // This assumes both the returned integers fit into a uint64_t but they are actually uint256 and dont have a good way of storing the 
    // full amount. In tests this will just mean that we need to keep our numbers below the 64bit max.
    std::string rewardsHex = result.substr(2 + 64-8, 8);
    std::string claimedHex = result.substr(2 + 64 + 64-8, 8);

    uint64_t rewards = std::stoull(rewardsHex, nullptr, 16);
    uint64_t claimed = std::stoull(claimedHex, nullptr, 16);

    return Recipient(rewards, claimed);
}

ethyl::Transaction ServiceNodeRewardsContract::liquidateBLSPublicKeyWithSignature(const std::string& pubkey, const uint64_t timestamp, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    ethyl::Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("liquidateBLSPublicKeyWithSignature((uint256,uint256),uint256,(uint256,uint256,uint256,uint256),uint64[])");
    std::string timestamp_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(timestamp), ethyl::utils::PaddingDirection::LEFT);
    // 8 Params: timestamp, 2x pubkey, 4x sig, pointer to array
    std::string indices_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(8*32), ethyl::utils::PaddingDirection::LEFT);
    indices_padded += ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(non_signer_indices.size()), ethyl::utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(index), ethyl::utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + pubkey + timestamp_padded + sig + indices_padded;

    return tx;
}

ethyl::Transaction ServiceNodeRewardsContract::removeBLSPublicKeyWithSignature(const std::string& pubkey, const uint64_t timestamp, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    ethyl::Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("removeBLSPublicKeyWithSignature((uint256,uint256),uint256,(uint256,uint256,uint256,uint256),uint64[])");
    std::string timestamp_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(timestamp), ethyl::utils::PaddingDirection::LEFT);
    // 8 Params: timestamp, 2x pubkey, 4x sig, pointer to array
    std::string indices_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(8*32), ethyl::utils::PaddingDirection::LEFT);
    indices_padded += ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(non_signer_indices.size()), ethyl::utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(index), ethyl::utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + pubkey + timestamp_padded + sig + indices_padded;

    return tx;
}

ethyl::Transaction ServiceNodeRewardsContract::initiateRemoveBLSPublicKey(const uint64_t service_node_id) {
    ethyl::Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("initiateRemoveBLSPublicKey(uint64)");
    std::string node_id_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(service_node_id), ethyl::utils::PaddingDirection::LEFT);
    tx.data = functionSelector + node_id_padded;
    return tx;
}

ethyl::Transaction ServiceNodeRewardsContract::removeBLSPublicKeyAfterWaitTime(const uint64_t service_node_id) {
    ethyl::Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("removeBLSPublicKeyAfterWaitTime(uint64)");
    std::string node_id_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(service_node_id), ethyl::utils::PaddingDirection::LEFT);
    tx.data = functionSelector + node_id_padded;
    return tx;
}

ethyl::Transaction ServiceNodeRewardsContract::updateRewardsBalance(const std::string& address, const uint64_t amount, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    ethyl::Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("updateRewardsBalance(address,uint256,(uint256,uint256,uint256,uint256),uint64[])");
    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    rewardAddressOutput = ethyl::utils::padTo32Bytes(rewardAddressOutput, ethyl::utils::PaddingDirection::LEFT);
    std::string amount_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(amount), ethyl::utils::PaddingDirection::LEFT);
    // 7 Params: addr, amount, 4x sig, pointer to array
    std::string indices_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(7*32), ethyl::utils::PaddingDirection::LEFT);
    indices_padded += ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(non_signer_indices.size()), ethyl::utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(index), ethyl::utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + rewardAddressOutput + amount_padded + sig + indices_padded;

    return tx;
}

ethyl::Transaction ServiceNodeRewardsContract::claimRewards() {
    ethyl::Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("claimRewards()");
    tx.data = functionSelector;
    return tx;
}

ethyl::Transaction ServiceNodeRewardsContract::claimRewards(uint64_t amount) {
    ethyl::Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("claimRewards(uint256)");
    std::string amount_padded = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(amount), ethyl::utils::PaddingDirection::LEFT);
    tx.data = functionSelector + amount_padded;
    return tx;
}

ethyl::Transaction ServiceNodeRewardsContract::start() {
    ethyl::Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = ethyl::utils::toEthFunctionSignature("start()");
    tx.data = functionSelector;
    return tx;
}
