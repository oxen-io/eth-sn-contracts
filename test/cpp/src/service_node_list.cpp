#include "service_node_rewards/service_node_list.hpp"
#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/utils.hpp"

#include <random>
#include <algorithm>

const std::string proofOfPossessionTag = "BLS_SIG_TRYANDINCREMENT_POP";
const std::string rewardTag = "BLS_SIG_TRYANDINCREMENT_REWARD";
const std::string removalTag = "BLS_SIG_TRYANDINCREMENT_REMOVE";
const std::string liquidateTag = "BLS_SIG_TRYANDINCREMENT_LIQUIDATE";

ServiceNode::ServiceNode(uint64_t _service_node_id) {
    service_node_id = _service_node_id;
    // This init function generates a secret key calling blsSecretKeySetByCSPRNG
    secretKey.init();
}

ServiceNode::~ServiceNode() {
}

std::string buildTag(const std::string& baseTag, uint32_t chainID, const std::string& contractAddress) {
    // Check if contractAddress starts with "0x" prefix
    std::string contractAddressOutput = contractAddress;
    if (contractAddressOutput.substr(0, 2) == "0x")
        contractAddressOutput = contractAddressOutput.substr(2);  // remove "0x"
    std::string concatenatedTag = "0x" + utils::toHexString(baseTag) + utils::padTo32Bytes(utils::decimalToHex(chainID), utils::PaddingDirection::LEFT) + contractAddressOutput;
    return utils::toHexString(utils::hash(concatenatedTag));
}

bls::Signature ServiceNode::signHash(const std::array<unsigned char, 32>& hash) const {
    bls::Signature sig;
    secretKey.signHash(sig, hash.data(), hash.size());
    return sig;
}

std::string ServiceNode::proofOfPossession(uint32_t chainID, const std::string& contractAddress, const std::string& senderEthAddress, const std::string& serviceNodePubkey) {
    std::string senderAddressOutput = senderEthAddress;
    if (senderAddressOutput.substr(0, 2) == "0x")
        senderAddressOutput = senderAddressOutput.substr(2);  // remove "0x"
    std::string fullTag = buildTag(proofOfPossessionTag, chainID, contractAddress);
    std::string message = "0x" + fullTag + getPublicKeyHex() + senderAddressOutput + utils::padTo32Bytes(utils::toHexString(serviceNodePubkey), utils::PaddingDirection::LEFT);
    const std::array<unsigned char, 32> hash = utils::hash(message);
    bls::Signature sig;
    secretKey.signHash(sig, hash.data(), hash.size());
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

std::string ServiceNodeList::aggregateSignatures(const std::string& message) {
    const std::array<unsigned char, 32> hash = utils::hash(message); // Get the hash of the input
    bls::Signature aggSig;
    aggSig.clear();
    for(auto& node : nodes) {
        aggSig.add(node.signHash(hash));
    }
    return utils::SignatureToHex(aggSig);
}

std::string ServiceNodeList::aggregateSignaturesFromIndices(const std::string& message, const std::vector<int64_t>& indices) {
    const std::array<unsigned char, 32> hash = utils::hash(message); // Get the hash of the input
    bls::Signature aggSig;
    aggSig.clear();
    for(auto& index : indices) {
        aggSig.add(nodes[static_cast<size_t>(index)].signHash(hash));
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

std::pair<std::string, std::string> ServiceNodeList::liquidateNodeFromIndices(uint64_t nodeID, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids) {
    std::string pubkey = nodes[static_cast<size_t>(findNodeIndex(nodeID))].getPublicKeyHex();
    std::string fullTag = buildTag(liquidateTag, chainID, contractAddress);
    std::string message = "0x" + fullTag + pubkey;
    const std::array<unsigned char, 32> hash = utils::hash(message);
    bls::Signature aggSig;
    aggSig.clear();
    for(auto& service_node_id: service_node_ids) {
        aggSig.add(nodes[static_cast<size_t>(findNodeIndex(service_node_id))].signHash(hash));
    }
    return std::make_pair(pubkey, utils::SignatureToHex(aggSig));
}

std::pair<std::string, std::string> ServiceNodeList::removeNodeFromIndices(uint64_t nodeID, uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids) {
    std::string pubkey = nodes[static_cast<size_t>(findNodeIndex(nodeID))].getPublicKeyHex();
    std::string fullTag = buildTag(removalTag, chainID, contractAddress);
    std::string message = "0x" + fullTag + pubkey;
    const std::array<unsigned char, 32> hash = utils::hash(message);
    bls::Signature aggSig;
    aggSig.clear();
    for(auto& service_node_id: service_node_ids) {
        aggSig.add(nodes[static_cast<size_t>(findNodeIndex(service_node_id))].signHash(hash));
    }
    return std::make_pair(pubkey, utils::SignatureToHex(aggSig));
}

std::string ServiceNodeList::updateRewardsBalance(const std::string& address, const uint64_t amount, const uint32_t chainID, const std::string& contractAddress, const std::vector<uint64_t>& service_node_ids) {
    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    std::string fullTag = buildTag(rewardTag, chainID, contractAddress);
    std::string message = "0x" + fullTag + utils::padToNBytes(rewardAddressOutput, 20, utils::PaddingDirection::LEFT) + utils::padTo32Bytes(std::to_string(amount), utils::PaddingDirection::LEFT);
    const std::array<unsigned char, 32> hash = utils::hash(message);
    bls::Signature aggSig;
    aggSig.clear();
    for(auto& service_node_id: service_node_ids) {
        aggSig.add(nodes[static_cast<size_t>(findNodeIndex(service_node_id))].signHash(hash));
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


