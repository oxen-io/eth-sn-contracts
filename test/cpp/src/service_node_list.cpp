#include "service_node_rewards/service_node_list.hpp"
#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/utils.hpp"
#include <oxenc/hex.h>

extern "C" {
#include "crypto/keccak.h"
}

#include <mcl/gmp_util.hpp>

#include <algorithm>
#include <chrono>
#include <random>
#include <cstring>

const std::string proofOfPossessionTag = "BLS_SIG_TRYANDINCREMENT_POP";
const std::string rewardTag = "BLS_SIG_TRYANDINCREMENT_REWARD";
const std::string removalTag = "BLS_SIG_TRYANDINCREMENT_REMOVE";
const std::string liquidateTag = "BLS_SIG_TRYANDINCREMENT_LIQUIDATE";
const std::string hashToG2Tag = "BLS_SIG_HASH_TO_FIELD_TAG";

ServiceNode::ServiceNode(uint64_t _service_node_id) {
    service_node_id = _service_node_id;
    // This init function generates a secret key calling blsSecretKeySetByCSPRNG
    secretKey.init();
}

static std::string buildTag(const std::string& baseTag, uint32_t chainID, std::string_view contractAddress) {
    // Check if contractAddress starts with "0x" prefix
    std::string contractAddressOutput = std::string(contractAddress);
    if (contractAddressOutput.substr(0, 2) == "0x")
        contractAddressOutput = contractAddressOutput.substr(2);  // remove "0x"
    std::string concatenatedTag = "0x" + oxenc::to_hex(baseTag) + ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(chainID), ethyl::utils::PaddingDirection::LEFT) + contractAddressOutput;
    auto hashed_tag = ethyl::utils::hashHex(concatenatedTag);
    return oxenc::to_hex(hashed_tag.begin(), hashed_tag.end());
}

static mcl::bn::G2 mapToG2(std::span<const uint8_t> msg, std::span<const uint8_t> hashToG2Tag) {

    mcl::bn::G2 result = {};
    result.clear();

    std::vector<uint8_t> messageWithI(msg.size() + 1);
    std::memcpy(messageWithI.data(), msg.data(), msg.size());

    // NOTE: The field modulus from Solidity BN256G2 in little endian
    // format.
    static const uint8_t FIELD_MODULUS_BYTES_LE[] = {
        0x47, 0xfd, 0x7c, 0xd8, 0x16, 0x8c, 0x20, 0x3c, 0x8d,
        0xca, 0x71, 0x68, 0x91, 0x6a, 0x81, 0x97, 0x5d, 0x58,
        0x81, 0x81, 0xb6, 0x45, 0x50, 0xb8, 0x29, 0xa0, 0x31,
        0xe1, 0x72, 0x4e, 0x64, 0x30,
    };

    mcl::Vint fieldModulus = {};
    fieldModulus.setArray(FIELD_MODULUS_BYTES_LE, sizeof(FIELD_MODULUS_BYTES_LE));

    for (uint8_t increment = 0;; increment++) {
        messageWithI[messageWithI.size() - 1] = increment;

        // NOTE: Solidity's BN256G2.hashToField(msg, tag) => x1, x2, b
        mcl::bn::Fp x1 = {}, x2 = {};
        bool b = {};
        {
            uint8_t expandedBytes[128] = {};
            utils::ExpandMessageXMDKeccak256(expandedBytes, messageWithI, hashToG2Tag);

            bool converted;
            x1.setBigEndianMod(&converted, expandedBytes + 0,  48);
            assert(converted);
            x2.setBigEndianMod(&converted, expandedBytes + 48, 48);
            assert(converted);

            b = ((expandedBytes[127] & 1) == 1);
        }

        // NOTE: herumi/bls MapTo::mapToEC
        mcl::bn::G2::Fp x = mcl::bn::G2::Fp(x1, x2);
        mcl::bn::G2::Fp y;
        mcl::bn::G2::getWeierstrass(y, x);
        if (mcl::bn::G2::Fp::squareRoot(y, y)) { // Check if this is a point
            if (b)                               // Let b => {0, 1} to choose between the two roots.
                y = -y;
            bool converted;
            result.set(&converted, x, y, false);
            assert(converted);
            return result;                       // Successfully mapped to curve, exit the loop
        }
    }

    return result;
}

bls::Signature ServiceNode::blsSignHash(std::span<const uint8_t> msg, uint32_t chainID, std::string_view contractAddress) const {
    // NOTE: This is herumi's 'blsSignHash' deconstructed to its primitive
    // function calls but instead of executing herumi's 'tryAndIncMapTo' which
    // maps a hash to a point we execute our own mapping function. herumi's
    // method increments the x-coordinate to try and map the point.
    //
    // This approach does not follow the original BLS paper's construction of the
    // hash to curve method which does `H(m||i)` e.g. it hashes the message with
    // an integer appended on the end. This integer is incremented and the
    // message is re-hashed if the resulting hash could not be mapped onto the
    // field.

    // NOTE: mcl::bn::blsSignHash(...) -> toG(...)
    // Map a string of `bytes` to a point on the curve for BLS
    mcl::bn::G2 Hm;
    {
        std::string hashToG2TagHex       = buildTag(hashToG2Tag, chainID, contractAddress);
        std::vector<uint8_t> hashToG2Tag = ethyl::utils::fromHexString<uint8_t>(hashToG2TagHex);
        Hm                               = mapToG2(msg, hashToG2Tag);
        mcl::bn::BN::param.mapTo.mulByCofactor(Hm);
    }

    // NOTE: mcl::bn::blsSignHash(...) -> GmulCT(...) -> G2::mulCT
    bls::Signature result = {};
    result.clear();
    {
        mcl::bn::Fr s;
        std::memcpy(const_cast<uint64_t*>(s.getUnit()), &secretKey.getPtr()->v, sizeof(s));
        static_assert(sizeof(s) == sizeof(secretKey.getPtr()->v));

        mcl::bn::G2 g2;
        mcl::bn::G2::mulCT(g2, Hm, s);
        std::memcpy(&result.getPtr()->v.x, &g2.x, sizeof(g2.x));
        std::memcpy(&result.getPtr()->v.y, &g2.y, sizeof(g2.y));
        std::memcpy(&result.getPtr()->v.z, &g2.z, sizeof(g2.z));
        static_assert(sizeof(g2) == sizeof(result.getPtr()->v));
    }

    return result;
}

// TODO(doyle): oxen-core has a new BLS implementation that can construct these
// messages directly as a byte stream and avoid the marshalling back-and-forth.
//
// For now we construct the hex strings then marshall to bytes for the BLS
// operations.
//
// In particular BLSSigner can be pulled into this repository as a utility class
// that can then be imported by oxen-core for use in the core-repo. This repo
// should contain all the contracts and bindings code (like BLSSigner) that help
// end-user applications like oxen-core interact with the contracts (such as
// creating a proof-of-posession).
//
// It will also allow this test repository to re-use that functionality for
// testing purposes.
std::string ServiceNode::proofOfPossession(uint32_t chainID, const std::string& contractAddress, const std::string& senderEthAddress, const std::string& serviceNodePubkey) {
    std::string senderAddressOutput = senderEthAddress;
    if (senderAddressOutput.substr(0, 2) == "0x")
        senderAddressOutput = senderAddressOutput.substr(2);  // remove "0x"
    std::string fullTag               = buildTag(proofOfPossessionTag, chainID, contractAddress);
    std::string message               = "0x" + fullTag + getPublicKeyHex() + senderAddressOutput + ethyl::utils::padTo32Bytes(oxenc::to_hex(serviceNodePubkey), ethyl::utils::PaddingDirection::LEFT);
    std::vector<uint8_t> messageBytes = ethyl::utils::fromHexString<uint8_t>(message);
    bls::Signature sig                = blsSignHash(messageBytes, chainID, contractAddress);
    return utils::SignatureToHex(sig);
}

std::string ServiceNode::getPublicKeyHex() const {
    bls::PublicKey publicKey;
    secretKey.getPublicKey(publicKey);
    return utils::BLSPublicKeyToHex(publicKey);
}

bls::PublicKey ServiceNode::getPublicKey() const {
    bls::PublicKey publicKey;
    secretKey.getPublicKey(publicKey);
    return publicKey;
}

ServiceNodeList::ServiceNodeList(size_t numNodes) {
    bls::init(mclBn_CurveSNARK1);
    mclBn_setMapToMode(MCL_MAP_TO_MODE_TRY_AND_INC);
    mcl::bn::G1 gen;
    bool b;
    mcl::bn::mapToG1(&b, gen, 1);
    blsPublicKey publicKey;
    publicKey.v = *reinterpret_cast<const mclBnG1*>(&gen); // Cast gen to mclBnG1 and assign it to publicKey.v

    blsSetGeneratorOfPublicKey(&publicKey);
    nodes.reserve(numNodes);
    for(size_t i = 0; i < numNodes; ++i) {
        nodes.emplace_back(next_service_node_id); // construct new ServiceNode in-place
        next_service_node_id++;
    }
}

ServiceNodeList::~ServiceNodeList() {
}

void ServiceNodeList::addNode() {
    nodes.emplace_back(next_service_node_id); // construct new ServiceNode in-plac
    next_service_node_id++;
}

void ServiceNodeList::deleteNode(uint64_t serviceNodeID) {
    auto it = std::find_if(nodes.begin(), nodes.end(), 
                           [serviceNodeID](const ServiceNode& node) {
                               return node.service_node_id == serviceNodeID;
                           });

    if (it != nodes.end()) {
        nodes.erase(it);
    }
    // Optionally, you can handle the case where the node is not found
}

std::string ServiceNodeList::getLatestNodePubkey() {
    return nodes.back().getPublicKeyHex();
}

std::string ServiceNodeList::aggregatePubkeyHex() {
    bls::PublicKey aggregate_pubkey; 
    aggregate_pubkey.clear();
    for(auto& node : nodes) {
        aggregate_pubkey.add(node.getPublicKey());
    }
    return utils::BLSPublicKeyToHex(aggregate_pubkey);
}

std::string ServiceNodeList::aggregateSignatures(const std::string& message, uint32_t chainID, std::string_view contractAddress) {
    bls::Signature aggSig;
    aggSig.clear();
    std::vector<uint8_t> messageBytes = ethyl::utils::fromHexString<uint8_t>(message);
    for(auto& node : nodes) {
        aggSig.add(node.blsSignHash(messageBytes, chainID, contractAddress));
    }
    return utils::SignatureToHex(aggSig);
}

std::string ServiceNodeList::aggregateSignaturesFromIndices(const std::string& message, const std::vector<int64_t>& indices, uint32_t chainID, std::string_view contractAddress) {
    bls::Signature aggSig;
    aggSig.clear();
    std::vector<uint8_t> messageBytes = ethyl::utils::fromHexString<uint8_t>(message);
    for(auto& index : indices) {
        aggSig.add(nodes[static_cast<size_t>(index)].blsSignHash(messageBytes, chainID, contractAddress));
    }
    return utils::SignatureToHex(aggSig);
}


std::vector<uint64_t> ServiceNodeList::findNonSigners(const std::vector<uint64_t>& serviceNodeIDs) {
    std::vector<uint64_t> nonSignerIndices = {};
    for (const auto& node: nodes) {
        auto it = std::find(serviceNodeIDs.begin(), serviceNodeIDs.end(), node.service_node_id);
        if (it == serviceNodeIDs.end()) {
            nonSignerIndices.push_back(node.service_node_id);
        }
    }
    return nonSignerIndices;
}

std::vector<uint64_t> ServiceNodeList::randomSigners(const size_t numOfRandomIndices) {
    if (numOfRandomIndices > nodes.size()) {
        throw std::invalid_argument("The number of random indices to choose is greater than the total number of indices available.");
    }

    std::vector<uint64_t> serviceNodeIDs(nodes.size());
    for (size_t i = 0; i < nodes.size(); ++i) {
        serviceNodeIDs[i] = nodes[i].service_node_id;
    }

    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(serviceNodeIDs.begin(), serviceNodeIDs.end(), g);

    serviceNodeIDs.resize(numOfRandomIndices);  // Reduce the size of the vector to numOfRandomIndices
    return serviceNodeIDs;
}

uint64_t ServiceNodeList::randomServiceNodeID() {
    std::vector<uint64_t> serviceNodeIDs(nodes.size());
    for (size_t i = 0; i < nodes.size(); ++i) {
        serviceNodeIDs[i] = nodes[i].service_node_id;
    }

    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(serviceNodeIDs.begin(), serviceNodeIDs.end(), g);

    return serviceNodeIDs[0];
}

std::tuple<std::string, uint64_t, std::string> ServiceNodeList::liquidateNodeFromIndices(uint64_t nodeID, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids) {
    std::string pubkey = nodes[static_cast<size_t>(findNodeIndex(nodeID))].getPublicKeyHex();
    std::string fullTag = buildTag(liquidateTag, chainID, contractAddress);
    auto timestamp = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count());
    std::string message = "0x" + fullTag + pubkey + ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(timestamp), ethyl::utils::PaddingDirection::LEFT);
    bls::Signature aggSig;
    aggSig.clear();
    std::vector<uint8_t> messageBytes = ethyl::utils::fromHexString<uint8_t>(message);
    for(auto& service_node_id: service_node_ids) {
        aggSig.add(nodes[static_cast<size_t>(findNodeIndex(service_node_id))].blsSignHash(messageBytes, chainID, contractAddress));
    }
    return std::make_tuple(pubkey, timestamp, utils::SignatureToHex(aggSig));
}

std::tuple<std::string, uint64_t, std::string> ServiceNodeList::removeNodeFromIndices(uint64_t nodeID, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids) {
    std::string pubkey = nodes[static_cast<size_t>(findNodeIndex(nodeID))].getPublicKeyHex();
    std::string fullTag = buildTag(removalTag, chainID, contractAddress);
    auto timestamp = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count());
    std::string message = "0x" + fullTag + pubkey + ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(timestamp), ethyl::utils::PaddingDirection::LEFT);
    bls::Signature aggSig;
    aggSig.clear();
    std::vector<uint8_t> messageBytes = ethyl::utils::fromHexString<uint8_t>(message);
    for(auto& service_node_id: service_node_ids) {
        aggSig.add(nodes[static_cast<size_t>(findNodeIndex(service_node_id))].blsSignHash(messageBytes, chainID, contractAddress));
    }
    return std::make_tuple(pubkey, timestamp, utils::SignatureToHex(aggSig));
}

std::string ServiceNodeList::updateRewardsBalance(const std::string& address, uint64_t amount, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids) {
    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    std::string fullTag = buildTag(rewardTag, chainID, contractAddress);
    std::string message = "0x" + fullTag + ethyl::utils::padToNBytes(rewardAddressOutput, 20, ethyl::utils::PaddingDirection::LEFT) + ethyl::utils::padTo32Bytes(std::to_string(amount), ethyl::utils::PaddingDirection::LEFT);
    bls::Signature aggSig;
    aggSig.clear();
    std::vector<uint8_t> messageBytes = ethyl::utils::fromHexString<uint8_t>(message);
    for(auto& service_node_id: service_node_ids) {
        aggSig.add(nodes[static_cast<size_t>(findNodeIndex(service_node_id))].blsSignHash(messageBytes, chainID, contractAddress));
    }
    return utils::SignatureToHex(aggSig);
}

int64_t ServiceNodeList::findNodeIndex(uint64_t service_node_id) {
    for (size_t i = 0; i < nodes.size(); ++i) {
        if (nodes[i].service_node_id == service_node_id) {
            return static_cast<int64_t>(i); // Cast size_t to int
        }
    }
    return -1; // Indicate that no node was found with the given id
}


