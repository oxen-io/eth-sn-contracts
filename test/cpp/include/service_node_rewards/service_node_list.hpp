#pragma once

#define BLS_ETH
#define MCLBN_FP_UNIT_SIZE 4
#define MCLBN_FR_UNIT_SIZE 4

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wshadow"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#include <bls/bls.hpp>
#include <mcl/bn.hpp>
#undef MCLBN_NO_AUTOLINK
#pragma GCC diagnostic pop

#include <chrono>
#include <optional>
#include <string>
#include <vector>
#include <span>

constexpr inline uint64_t SERVICE_NODE_LIST_SENTINEL = 0;

class ServiceNode {
private:
    bls::SecretKey secretKey;
public:
    uint64_t service_node_id = SERVICE_NODE_LIST_SENTINEL;
    ServiceNode() = default;
    ServiceNode(uint64_t _service_node_id);
    bls::Signature blsSignHash(std::span<const uint8_t> bytes, uint32_t chainID, std::string_view contractAddress) const;
    std::string    proofOfPossession(uint32_t chainID, const std::string& contractAddress, const std::string& senderEthAddress, const std::string& serviceNodePubkey);
    std::string    getPublicKeyHex() const;
    bls::PublicKey getPublicKey() const;
};

class ServiceNodeList {
public:
    std::vector<ServiceNode> nodes;
    uint64_t                 next_service_node_id = SERVICE_NODE_LIST_SENTINEL + 1;

    ServiceNodeList(size_t numNodes);
    ~ServiceNodeList();

    void addNode();
    void deleteNode(uint64_t serviceNodeID);
    std::string getLatestNodePubkey();

    std::string aggregatePubkeyHex();
    std::string aggregateSignatures(const std::string& message, uint32_t chainID, std::string_view contractAddress);
    std::string aggregateSignaturesFromIndices(const std::string& message, const std::vector<int64_t>& indices, uint32_t chainID, std::string_view contractAddress);

    std::tuple<std::string, uint64_t, std::string> liquidateNodeFromIndices(
            uint64_t nodeID,
            uint32_t chainID,
            const std::string& contractAddress,
            const std::vector<uint64_t>& indices,
            std::optional<std::chrono::system_clock::time_point> timestamp = std::nullopt) {
        return exitNodeFromIndices(nodeID, chainID, contractAddress, indices, timestamp, true);
    }
    std::tuple<std::string, uint64_t, std::string> exitNodeFromIndices(
            uint64_t nodeID,
            uint32_t chainID,
            const std::string& contractAddress,
            const std::vector<uint64_t>& indices,
            std::optional<std::chrono::system_clock::time_point> timestamp = std::nullopt,
            bool liquidate = false);
    std::string updateRewardsBalance(const std::string& address, uint64_t amount, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids);

    std::vector<uint64_t> findNonSigners(const std::vector<uint64_t>& indices);
    std::vector<uint64_t> randomSigners(const size_t numOfRandomIndices);
    int64_t findNodeIndex(uint64_t service_node_id);
    uint64_t randomServiceNodeID();

// End Service Node List
};
