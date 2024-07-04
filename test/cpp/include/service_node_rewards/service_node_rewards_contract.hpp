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

struct Contributor {
    std::array<unsigned char, 20> address;
    uint64_t                      amount;
};

struct ContractServiceNode {
    uint64_t                      next;
    uint64_t                      prev;
    std::array<unsigned char, 20> recipient;
    bls::PublicKey                pubkey;
    uint64_t                      leaveRequestTimestamp;
    std::string                   deposit;
    std::array<Contributor, 10>   contributors;
};

class ServiceNodeRewardsContract {
public:
    // TODO: Taken from scripts/deploy-local-test.js and hardcoded
    static constexpr inline uint64_t STAKING_REQUIREMENT = 120'000'000'000;

    // Method for creating a transaction to add a public key
    Transaction addBLSPublicKey(const std::string& publicKey, const std::string& sig, const std::string& serviceNodePubkey, const std::string& serviceNodeSignature, uint64_t fee);

    ContractServiceNode serviceNodes(uint64_t index);
    uint64_t            serviceNodeIDs(const bls::PublicKey& pKey);
    uint64_t            serviceNodesLength();
    uint64_t            maxPermittedPubkeyAggregations();
    std::string         designatedToken();
    std::string         aggregatePubkeyString();
    bls::PublicKey      aggregatePubkey();
    Recipient           viewRecipientData(const std::string& address);

    Transaction liquidateBLSPublicKeyWithSignature(const std::string& pubkey, const uint64_t timestamp, const std::string& sig, const std::vector<uint64_t>& non_signer_indices);
    Transaction initiateRemoveBLSPublicKey(const uint64_t service_node_id);
    Transaction removeBLSPublicKeyAfterWaitTime(const uint64_t service_node_id);
    Transaction removeBLSPublicKeyWithSignature(const std::string& pubkey, const uint64_t timestamp, const std::string& sig, const std::vector<uint64_t>& non_signer_indices);
    Transaction updateRewardsBalance(const std::string& address, const uint64_t amount, const std::string& sig, const std::vector<uint64_t>& non_signer_indices);
    Transaction claimRewards();
    Transaction start();

    /// Address of the ERC20 contract that must be set to the address of the
    /// contract on the blockchain for the functions to succeed. If the contract
    /// is not set, the functions that communicate with the provider will send
    /// to the 0 address.
    std::string contractAddress;

    /// Provider must be set with an RPC client configure to allow the contract
    /// to communicate with the blockchain. If the provider is not setup, the
    /// functions that require a provider will throw.
    ethyl::Provider provider;
};
