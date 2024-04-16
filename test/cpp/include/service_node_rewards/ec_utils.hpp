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

namespace utils
{
    std::string                   BLSPublicKeyToHex(bls::PublicKey publicKey);
    bls::PublicKey                HexToBLSPublicKey(std::string_view hex);
    std::string                   SignatureToHex(bls::Signature sig);
    std::array<unsigned char, 32> HashModulus(std::string message);
}
