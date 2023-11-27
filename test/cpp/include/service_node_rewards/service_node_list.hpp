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
    ServiceNode();
    ~ServiceNode();
    bls::Signature signHash(const std::array<unsigned char, 32>& hash);
    std::string proofOfPossession(uint32_t chainID, const std::string& contractAddress);
    std::string getPublicKeyHex();
    bls::PublicKey getPublicKey();
// End Service Node
};

class ServiceNodeList {
public:
    std::vector<ServiceNode> nodes;

    ServiceNodeList(size_t numNodes);
    ~ServiceNodeList();

    void addNode();
    std::string getLatestNodePubkey();

    std::string aggregatePubkeyHex();
    std::string aggregateSignatures(const std::string& message);
    std::string aggregateSignaturesFromIndices(const std::string& message, const std::vector<int64_t>& indices);

    std::vector<int64_t> findNonSigners(const std::vector<int64_t>& indices);
    std::vector<int64_t> randomSigners(const size_t numOfRandomIndices);

// End Service Node List
};
