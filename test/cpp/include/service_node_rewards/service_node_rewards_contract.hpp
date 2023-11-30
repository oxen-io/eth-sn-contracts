#pragma once
#include <string>
#include <vector>
#include <memory>

#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/provider.hpp"
#include "ethyl/transaction.hpp"

class ServiceNodeRewardsContract {
public:
    // Constructor
    ServiceNodeRewardsContract(const std::string& _contractAddress, std::shared_ptr<Provider> _provider);

    // Method for creating a transaction to add a public key
    Transaction addBLSPublicKey(const std::string& publicKey, const std::string& sig);

    uint64_t serviceNodesLength();
    std::string designatedToken();
    std::string aggregatePubkey();

    Transaction liquidateBLSPublicKeyWithSignature(const uint64_t service_node_id, const std::string& sig, const std::vector<uint64_t>& non_signer_indices);
    Transaction initiateRemoveBLSPublicKey(const uint64_t service_node_id);

    Transaction checkSigAGG(const std::string& sig, const std::string& message);
    Transaction checkAggPubkey(const std::string& aggPubkey);
    Transaction checkSigAGGIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& indices);
    Transaction checkSigAGGNegateIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& non_signer_indices);

private:
    std::string contractAddress;
    std::shared_ptr<Provider> provider;
};
