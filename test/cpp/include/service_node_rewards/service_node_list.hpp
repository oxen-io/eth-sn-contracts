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

#include <string>
#include <vector>

class ServiceNode {
private:
    bls::SecretKey secretKey;
public:
    uint64_t service_node_id;
    ServiceNode(uint64_t _service_node_id);
    ~ServiceNode();
    bls::Signature signHash(const std::array<unsigned char, 32>& hash) const;
    std::string    proofOfPossession(uint32_t chainID, const std::string& contractAddress, const std::string& senderEthAddress, const std::string& serviceNodePubkey);
    std::string    getPublicKeyHex() const;
    bls::PublicKey getPublicKey() const;
};

class ServiceNodeList {
public:
    uint64_t next_service_node_id = 1;
    std::vector<ServiceNode> nodes;

    ServiceNodeList(size_t numNodes);
    ~ServiceNodeList();

    void addNode();
    void deleteNode(uint64_t serviceNodeID);
    std::string getLatestNodePubkey();

    std::string aggregatePubkeyHex();
    std::string aggregateSignatures(const std::string& message);
    std::string aggregateSignaturesFromIndices(const std::string& message, const std::vector<int64_t>& indices);

    std::pair<std::string, std::string> liquidateNodeFromIndices(uint64_t nodeID, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& indices);
    std::pair<std::string, std::string> removeNodeFromIndices(uint64_t nodeID, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& indices);
    std::string updateRewardsBalance(const std::string& address, const uint64_t amount, const uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids);

    std::vector<uint64_t> findNonSigners(const std::vector<uint64_t>& indices);
    std::vector<uint64_t> randomSigners(const size_t numOfRandomIndices);
    int64_t findNodeIndex(uint64_t service_node_id);
    uint64_t randomServiceNodeID();

// End Service Node List
};
