#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/utils.hpp"

#include <cybozu/endian.hpp>
#include <cstring>

extern "C" {
#include <crypto/keccak.h>
}

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

    std::string result = oxenc::to_hex(serialized_signature.begin(), serialized_signature.end());
    return result;
}

std::string utils::BLSPublicKeyToHex(const bls::PublicKey& publicKey) {
    const mclSize                                     KEY_SIZE         = 32;
    std::array<char, KEY_SIZE * 2 /*X, Y component*/> serializedKeyHex = {};

    char*               dst     = serializedKeyHex.data();
    const blsPublicKey* rawKey  = publicKey.getPtr();

    mcl::bn::G1 g1Point = {};
    g1Point.clear();

    // NOTE: const_cast is legal because the original g1Point was not declared
    // const
    static_assert(sizeof(*g1Point.x.getUnit()) * g1Point.x.maxSize == sizeof(rawKey->v.x.d),
                  "We memcpy the key X,Y,Z component into G1 point's X,Y,Z component, hence, the sizes must match");
    std::memcpy(const_cast<uint64_t*>(g1Point.x.getUnit()), rawKey->v.x.d, sizeof(rawKey->v.x.d));
    std::memcpy(const_cast<uint64_t*>(g1Point.y.getUnit()), rawKey->v.y.d, sizeof(rawKey->v.y.d));
    std::memcpy(const_cast<uint64_t*>(g1Point.z.getUnit()), rawKey->v.z.d, sizeof(rawKey->v.z.d));
    g1Point.normalize();

    if (g1Point.x.serialize(dst, KEY_SIZE, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of x is zero");
    if (g1Point.y.serialize(dst + KEY_SIZE, KEY_SIZE, mcl::IoSerialize | mcl::IoBigEndian) == 0)
        throw std::runtime_error("size of y is zero");

    std::string result = oxenc::to_hex(serializedKeyHex.begin(), serializedKeyHex.end());
    return result;
}

bls::PublicKey utils::HexToBLSPublicKey(std::string_view hex) {
    const size_t BLS_PKEY_COMPONENT_HEX_SIZE = 32 * 2;
    const size_t BLS_PKEY_HEX_SIZE           = BLS_PKEY_COMPONENT_HEX_SIZE * 2;
    hex                                      = ethyl::utils::trimPrefix(hex, "0x");

    if (hex.size() != BLS_PKEY_HEX_SIZE) {
        std::stringstream stream;
        stream << "Failed to deserialize BLS key hex '" << hex << "': A serialized BLS key is " << BLS_PKEY_HEX_SIZE << " hex characters, input hex was " << hex.size() << " characters";
        throw std::runtime_error(stream.str());
    }

    // NOTE: Divide the 2 keys into the X,Y component
    std::string_view              pkeyXHex = hex.substr(0,                           BLS_PKEY_COMPONENT_HEX_SIZE);
    std::string_view              pkeyYHex = hex.substr(BLS_PKEY_COMPONENT_HEX_SIZE, BLS_PKEY_COMPONENT_HEX_SIZE);
    std::array<unsigned char, 32> pkeyX    = ethyl::utils::fromHexString32Byte(pkeyXHex);
    std::array<unsigned char, 32> pkeyY    = ethyl::utils::fromHexString32Byte(pkeyYHex);

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
    std::array<unsigned char, 32> hash = ethyl::utils::hashBytes(message);
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

void utils::ExpandMessageXMDKeccak256(std::span<uint8_t> out, std::span<const uint8_t> msg, std::span<const uint8_t> dst)
{
    // NOTE: Setup parameters (note: Our implementation restricts the output to <= 256 bytes)
    const size_t KECCAK256_OUTPUT_SIZE = 256 / 8;
    const uint16_t len_in_bytes        = static_cast<uint16_t>(out.size());
    const size_t b_in_bytes            = KECCAK256_OUTPUT_SIZE; // the output size of H [Keccak] in bits
    const size_t ell                   = len_in_bytes / b_in_bytes;

    // NOTE: Assert invariants
    assert((out.size() % KECCAK256_OUTPUT_SIZE) == 0 && 0 < out.size() && out.size() <= 256);
    assert(dst.size() <= 255);

    // NOTE: Construct (4) Z_pad
    //
    //   s_in_bytes = Input Block Size     = 1088 bits = 136 bytes
    //   Z_pad      = I2OSP(0, s_in_bytes) = [0 .. INPUT_BLOCK_SIZE) => {0 .. 0}
    const        size_t  INPUT_BLOCK_SIZE        = 136;
    static const uint8_t Z_pad[INPUT_BLOCK_SIZE] = {};

    // NOTE: Construct (5) l_i_b_str
    //
    //   l_i_b_str    = I2OSP(len_in_bytes, 2) => output length expressed in big
    //                  endian in 2 bytes.
    uint8_t l_i_b_str[2];
    cybozu::Set16bitAsBE(l_i_b_str, static_cast<uint16_t>(out.size()));

    // NOTE: Construct I2OSP(len(DST), 1) for DST_prime
    //   DST_prime          = (DST || I2OSP(len(DST), 1)
    //   I2OSP(len(DST), 1) = DST length expressed in big endian as 1 byte.
    uint8_t I2OSP_0_1 = 0;
    uint8_t I2OSP_len_dst = static_cast<uint8_t>(dst.size());

    // NOTE: Construct (7) b0 = H(msg_prime)
    uint8_t b0[KECCAK256_OUTPUT_SIZE] = {};
    {
        // NOTE: Construct (6) msg_prime = Z_pad || msg || l_i_b_str || I2OSP(0, 1) || DST_prime
        KECCAK_CTX msg_prime = {};
        keccak_init(&msg_prime);
        keccak_update(&msg_prime, Z_pad, sizeof(Z_pad));
        keccak_update(&msg_prime, msg.data(), msg.size());
        keccak_update(&msg_prime, l_i_b_str, sizeof(l_i_b_str));
        keccak_update(&msg_prime, &I2OSP_0_1, sizeof(I2OSP_0_1));
        keccak_update(&msg_prime, dst.data(), dst.size());
        keccak_update(&msg_prime, &I2OSP_len_dst, sizeof(I2OSP_len_dst));

        // NOTE: Executes H(msg_prime)
        keccak_finish(&msg_prime, b0);
    }

    // NOTE: Construct (8) b1 = H(b0 || I2OSP(1, 1) || DST_prime)
    uint8_t b1[KECCAK256_OUTPUT_SIZE] = {};
    {
        uint8_t I2OSP_1_1 = 1;
        KECCAK_CTX ctx    = {};
        keccak_init(&ctx);
        keccak_update(&ctx, b0, sizeof(b0));
        keccak_update(&ctx, &I2OSP_1_1, sizeof(I2OSP_1_1));
        keccak_update(&ctx, dst.data(), dst.size());
        keccak_update(&ctx, &I2OSP_len_dst, sizeof(I2OSP_len_dst));

        // NOTE: Executes H(...)
        keccak_finish(&ctx, b1);
    }

    // NOTE: Construct (11) uniform_bytes = b1 ... b_ell
    std::memcpy(out.data(), b1, sizeof(b1));

    for (size_t i = 1; i < ell; i++) {

        // NOTE: Construct strxor(b0, b(i-1))
        uint8_t strxor_b0_bi[KECCAK256_OUTPUT_SIZE] = {};
        for (size_t j = 0; j < KECCAK256_OUTPUT_SIZE; j++) {
            strxor_b0_bi[j] = b0[j] ^ out[KECCAK256_OUTPUT_SIZE * (i - 1) + j];
        }

        // NOTE: Construct (10) bi = H(strxor(b0, b(i - 1)) || I2OSP(i, 1) || DST_prime)
        uint8_t bi[KECCAK256_OUTPUT_SIZE] = {};
        {
            uint8_t I2OSP_i_1 = static_cast<uint8_t>(i + 1);
            KECCAK_CTX ctx    = {};
            keccak_init(&ctx);
            keccak_update(&ctx, strxor_b0_bi, sizeof(strxor_b0_bi));
            keccak_update(&ctx, &I2OSP_i_1, sizeof(I2OSP_i_1));
            keccak_update(&ctx, dst.data(), dst.size());
            keccak_update(&ctx, &I2OSP_len_dst, sizeof(I2OSP_len_dst));

            // NOTE: Executes H(...)
            keccak_finish(&ctx, bi);
        }

        // NOTE: Transfer bi to uniform_bytes
        std::memcpy(out.data() + KECCAK256_OUTPUT_SIZE * i, bi, sizeof(bi));
    }
}
