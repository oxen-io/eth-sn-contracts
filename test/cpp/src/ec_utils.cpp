#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/utils.hpp"

#include <cstring>

std::string utils::SignatureToHex(bls::Signature sig) {
    mclSize serializedSignatureSize = 32;
    std::vector<unsigned char> serialized_signature(serializedSignatureSize*4);
    uint8_t *dst = serialized_signature.data();
    const blsSignature* blssig = sig.getPtr();  
    const mcl::bn::G2* g2Point = reinterpret_cast<const mcl::bn::G2*>(&blssig->v);
    mcl::bn::G2 g2Point2 = *g2Point;
    g2Point2.normalize();
    if (g2Point2.x.a.serialize(dst, serializedSignatureSize, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of x.a is zero");
    if (g2Point2.x.b.serialize(dst + serializedSignatureSize, serializedSignatureSize, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of x.b is zero");
    if (g2Point2.y.a.serialize(dst + serializedSignatureSize * 2, serializedSignatureSize, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of y.a is zero");
    if (g2Point2.y.b.serialize(dst + serializedSignatureSize * 3, serializedSignatureSize, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of y.b is zero");
    return utils::toHexString(serialized_signature);
}

std::string utils::BLSPublicKeyToHex(bls::PublicKey publicKey) {
    mclSize                    serializedPublicKeySize = 32;
    std::vector<unsigned char> serialized_pubkey(serializedPublicKeySize * 2);
    uint8_t*                   dst      = serialized_pubkey.data();
    const blsPublicKey*        pub      = publicKey.getPtr();
    const mcl::bn::G1*         g1Point  = reinterpret_cast<const mcl::bn::G1*>(&pub->v);
    mcl::bn::G1                g1Point2 = *g1Point;
    g1Point2.normalize();
    if (g1Point2.x.serialize(dst, serializedPublicKeySize, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of x is zero");
    if (g1Point2.y.serialize(dst + serializedPublicKeySize, serializedPublicKeySize, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of y is zero");
    return utils::toHexString(serialized_pubkey);
}

bls::PublicKey utils::HexToBLSPublicKey(std::string_view hex) {
    const size_t BLS_PKEY_COMPONENT_HEX_SIZE = 32 * 2;
    const size_t BLS_PKEY_HEX_SIZE           = BLS_PKEY_COMPONENT_HEX_SIZE * 2;
    hex                                      = utils::trimPrefix(hex, "0x");

    if (hex.size() != BLS_PKEY_HEX_SIZE) {
        std::stringstream stream;
        stream << "Failed to deserialize BLS key hex '" << hex << "': A serialized BLS key is " << BLS_PKEY_HEX_SIZE << " hex characters, input hex was " << hex.size() << " characters";
        throw std::runtime_error(stream.str());
    }

    // NOTE: Divide the 2 keys into the X,Y component
    std::string_view              pkeyXHex = hex.substr(0,                           BLS_PKEY_COMPONENT_HEX_SIZE);
    std::string_view              pkeyYHex = hex.substr(BLS_PKEY_COMPONENT_HEX_SIZE, BLS_PKEY_COMPONENT_HEX_SIZE);
    std::array<unsigned char, 32> pkeyX    = utils::fromHexString32Byte(pkeyXHex);
    std::array<unsigned char, 32> pkeyY    = utils::fromHexString32Byte(pkeyYHex);

    // NOTE: In `PublicKeyToHex` before we serialize the G1 point, we normalize
    // the point which divides X, Y by the Z component. This transformation then
    // converts the divisor to 1 (Z) as the division has already been applied to
    // X and Y. Here we reconstruct Z as 1.
    std::array<unsigned char, 32> pkeyZ = {};
    pkeyZ.data()[0]                     = 1;

    // NOTE: This is the reverse of utils::PublicKeyToHex (above). We serialize
    // a G1 point to conform the required format to interop directly with
    // Solidity's BN256G1 library.
    mcl::bn::G1 g1Point = {};
    g1Point.clear(); // NOTE: Default init has *uninitialized values*!

    // NOTE: Deserialize the components back into the point.
    size_t readX = g1Point.x.deserialize(pkeyX.data(), pkeyX.size(), mcl::IoSerialize | mcl::IoBigEndian);
    size_t readY = g1Point.y.deserialize(pkeyY.data(), pkeyY.size(), mcl::IoSerialize | mcl::IoBigEndian);
    size_t readZ = g1Point.z.deserialize(pkeyZ.data(), pkeyZ.size(), mcl::IoSerialize);

    // NOTE: This is hardcoded so it should always succeed, if not something
    // bad has gone wrong.
    assert(readZ == pkeyZ.size());

    if (readX != pkeyX.size()) {
        std::stringstream stream;
        stream << "Failed to deserialize BLS key 'x' component '" << pkeyXHex << "', input hex was: '" << hex << "'";
        throw std::runtime_error(stream.str());
    }

    if (readY != pkeyY.size()) {
        std::stringstream stream;
        stream << "Failed to deserialize BLS key 'y' component '" << pkeyYHex << "', input hex was: '" << hex << "'";
        throw std::runtime_error(stream.str());
    }

    // TODO: It's impossible to create a bls::PublicKey from a G1 point through
    // the C++ interface. It allows deserialization from a hex string, but, the
    // hex string must originally have been serialised through its member
    // function.
    //
    // Since we have a custom format for Solidity, although we can reconstruct
    // the individual components of the public key in binary we have to go a
    // roundabout way to restore these bytes into the key.
    //
    // const_cast away the pointer which is legal because the original object
    // was not declared const.
    bls::PublicKey result = {};
    blsPublicKey*  rawKey = const_cast<blsPublicKey*>(result.getPtr());
    std::memcpy(rawKey->v.x.d, g1Point.x.getUnit(), sizeof(rawKey->v.x.d));
    std::memcpy(rawKey->v.y.d, g1Point.y.getUnit(), sizeof(rawKey->v.y.d));
    std::memcpy(rawKey->v.z.d, g1Point.z.getUnit(), sizeof(rawKey->v.z.d));

    return result;
}

std::array<unsigned char, 32> utils::HashModulus(std::string message) {
    std::array<unsigned char, 32> hash = utils::hash(message);
    mcl::bn::Fp x;
    x.clear();
    x.setArrayMask(hash.data(), hash.size());
    std::array<unsigned char, 32> serialized_hash;
    uint8_t *hdst = serialized_hash.data();
    mclSize serializedSignatureSize = 32;
    if (x.serialize(hdst, serializedSignatureSize, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of x is zero");
    return serialized_hash;
}
