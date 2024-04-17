#pragma once
#include <string>
#include <string_view>
#include <vector>
#include <memory>

#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/provider.hpp"
#include "ethyl/transaction.hpp"

struct Recipient {
    uint64_t rewards;
    uint64_t claimed;

    // Constructor for easy initialization
    Recipient(uint64_t _rewards, uint64_t _claimed) : rewards(_rewards), claimed(_claimed) {}
};

struct ContractServiceNode {
    uint64_t                      next;
    uint64_t                      prev;
    std::array<unsigned char, 20> recipient;
    bls::PublicKey                pubkey;
    uint64_t                      leaveRequestTimestamp;
    std::string                   deposit;
};

class ServiceNodeRewardsContract {
public:
    // TODO: Taken from scripts/deploy-local-test.js and hardcoded
    static constexpr inline uint64_t STAKING_REQUIREMENT = 100'000'000'000;

    // Constructor
    ServiceNodeRewardsContract(const std::string& _contractAddress, std::shared_ptr<Provider> _provider);

    // Method for creating a transaction to add a public key
    Transaction addBLSPublicKey(const std::string& publicKey, const std::string& sig, const std::string& serviceNodePubkey, const std::string& serviceNodeSignature, uint64_t fee);

    ContractServiceNode serviceNodes(uint64_t index);
    uint64_t            serviceNodeIDs(const bls::PublicKey& pKey);
    uint64_t            serviceNodesLength();
    std::string         designatedToken();
    std::string         aggregatePubkey();
    Recipient           viewRecipientData(const std::string& address);

    Transaction liquidateBLSPublicKeyWithSignature(const uint64_t service_node_id, const std::string& pubkey, const std::string& sig, const std::vector<uint64_t>& non_signer_indices);
    Transaction initiateRemoveBLSPublicKey(const uint64_t service_node_id);
    Transaction removeBLSPublicKeyAfterWaitTime(const uint64_t service_node_id);
    Transaction removeBLSPublicKeyWithSignature(const uint64_t service_node_id, const std::string& pubkey, const std::string& sig, const std::vector<uint64_t>& non_signer_indices);
    Transaction updateRewardsBalance(const std::string& address, const uint64_t amount, const std::string& sig, const std::vector<uint64_t>& non_signer_indices);
    Transaction claimRewards();
    Transaction start();

private:
    std::string contractAddress;
    std::shared_ptr<Provider> provider;
};
