#include "service_node_rewards/service_node_list.hpp"
#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/utils.hpp"

#include <random>

const std::string proofOfPossessionTag = "BLS_SIG_TRYANDINCREMENT_POP";
const std::string rewardTag = "BLS_SIG_TRYANDINCREMENT_REWARD";
const std::string removalTag = "BLS_SIG_TRYANDINCREMENT_REMOVE";
const std::string liquidateTag = "BLS_SIG_TRYANDINCREMENT_LIQUIDATE";

ServiceNode::ServiceNode() {
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
    return utils::toHexString(baseTag) + utils::padTo32Bytes(utils::decimalToHex(chainID), utils::PaddingDirection::LEFT) + contractAddressOutput;
}

bls::Signature ServiceNode::signHash(const std::array<unsigned char, 32>& hash) {
    bls::Signature sig;
    secretKey.signHash(sig, hash.data(), hash.size());
    return sig;
}

std::string ServiceNode::proofOfPossession(uint32_t chainID, const std::string& contractAddress) {
    std::string fullTag = buildTag(proofOfPossessionTag, chainID, contractAddress);
    std::string message = "0x" + fullTag + getPublicKeyHex();
    const std::array<unsigned char, 32> hash = utils::hash(message);
    bls::Signature sig;
    secretKey.signHash(sig, hash.data(), hash.size());
    return utils::SignatureToHex(sig);
}

std::string ServiceNode::getPublicKeyHex() {
    bls::PublicKey publicKey;
    secretKey.getPublicKey(publicKey);
    return utils::PublicKeyToHex(publicKey);
}

bls::PublicKey ServiceNode::getPublicKey() {
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
        nodes.emplace_back(); // construct new ServiceNode in-place
    }
}

ServiceNodeList::~ServiceNodeList() {
}

void ServiceNodeList::addNode() {
    nodes.emplace_back(); // construct new ServiceNode in-place
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
    return utils::PublicKeyToHex(aggregate_pubkey);
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


std::vector<int64_t> ServiceNodeList::findNonSigners(const std::vector<int64_t>& indices) {
    std::vector<int64_t> nonSignerIndices = {};
    for (int64_t i = 0; i < static_cast<int64_t>(nodes.size()); ++i) {
        if (std::find(indices.begin(), indices.end(), i) == indices.end()) {
            nonSignerIndices.push_back(i);
        }
    }
    return nonSignerIndices;
}

std::vector<int64_t> ServiceNodeList::randomSigners(const size_t numOfRandomIndices) {
    if (numOfRandomIndices > nodes.size()) {
        throw std::invalid_argument("The number of random indices to choose is greater than the total number of indices available.");
    }

    std::vector<int64_t> indices(nodes.size());
    for (int64_t i = 0; i < static_cast<int64_t>(nodes.size()); ++i) {
        indices[static_cast<size_t>(i)] = i;
    }

    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(indices.begin(), indices.end(), g);

    indices.resize(numOfRandomIndices);  // Reduce the size of the vector to numOfRandomIndices
    return indices;
}


