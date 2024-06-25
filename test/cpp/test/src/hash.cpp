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
#include <mcl/fp.hpp>
#include <mcl/mapto_wb19.hpp>
#undef MCLBN_NO_AUTOLINK
#pragma GCC diagnostic pop

#include <iostream>
#include <iomanip>
#include <algorithm>

#include "service_node_rewards/ec_utils.hpp"
#include "ethyl/utils.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

//using namespace mcl;
//using namespace mcl::bn;

//typedef mcl::MapTo_WB19<Fp, G1, Fp2, G2> MapTo;
//typedef MapTo::E2 E2;



//void printHexMD(const uint8_t md[256]) {
    //for (int i = 0; i < 256; ++i) {
        //std::cout << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(md[i]);
        //if ((i + 1) % 16 == 0) {
            //std::cout << std::endl;
        //} else {
            //std::cout << " ";
        //}
    //}
//}

//std::string stringToHex(const std::string& input)
//{
    //std::stringstream ss;
    //ss << std::hex << std::setfill('0');
    //for (char c : input)
        //ss << std::setw(2) << static_cast<int>(static_cast<unsigned char>(c));
    //return ss.str();
//}

std::array<std::string, 3> convertToHexStrings(const uint8_t md[96]) {
    std::array<std::string, 3> result;
    
    for (int i = 0; i < 3; ++i) {
        std::stringstream ss;
        ss << "0x";
        for (int j = 0; j < 32; ++j) {
            ss << std::setfill('0') << std::setw(2) << std::hex << static_cast<int>(md[i * 32 + j]);
        }
        result[i] = ss.str();
    }
    
    return result;
}

TEST_CASE( "expand message using keccak", "[hashToField]" ) {
    const char *msg = "asdf";
    uint8_t md[96];
    mcl::fp::expand_message_xmd_hash(md, sizeof(md), msg, 4, msg, 4, utils::hash);

    const auto hexStrings = convertToHexStrings(md);
    //for (const auto& hexString : hexStrings) {
        //std::cout << hexString << std::endl;
    //}

    // Should match the results from the smart contracts
    //
    //     describe("expand_message_xmd_keccak256", function () {
    //       it.only("should not revert", async function () {
    //         const message = "asdf";
    //         const hexMsg = ethers.hexlify(ethers.toUtf8Bytes(message));
    //         console.log(hexMsg);
    //         await expect(hashToField.expand_message_xmd_keccak256(hexMsg, hexMsg)).to.not.be.reverted;
    //         console.log(await hashToField.expand_message_xmd_keccak256(hexMsg, hexMsg));
    //       });
    //     });
    REQUIRE(hexStrings[0] == "0xb7dfc070382dc6f51e559031b14d8f0f2a573d61127c7cb791d4b4608a74ff01");
    REQUIRE(hexStrings[1] == "0x6d9ce93fab2366b5ce3c850bbd8835e879af2a342ad6bffbaf731fb93126a3f4");
    REQUIRE(hexStrings[2] == "0x8a82641e464475fe7637f75324eef9a103cbbf53ec1a3324c1e0baf6b05e92e5");
}

TEST_CASE( "hash to fp2", "[hashToField]" ) {
    bls::init(mclBn_CurveSNARK1);
    const char *msg = "asdf";
    uint8_t md[96];
    mcl::fp::expand_message_xmd_hash(md, sizeof(md), msg, 4, msg, 4, utils::hash);

    mcl::bn::Fp out[2];
    bool b;
    out[0].setBigEndianMod(&b, &md[0], 48);
    assert(b); (void)b;
    out[1].setBigEndianMod(&b, &md[48], 48);
    assert(b); (void)b;

    std::ostringstream oss;
    out[0].save(&b, oss, mcl::IoAuto);
    std::ostringstream oss2;
    out[1].save(&b, oss2, mcl::IoAuto);

    //    describe("hash_to_field", function () {
    //      it.only("should return two uint256 values", async function () {
    //        const message = "asdf";
    //        const hexMsg = ethers.hexlify(ethers.toUtf8Bytes(message));
    //    
    //        const result = await hashToField.hash_to_field(hexMsg, hexMsg);
    //    
    //        expect(result).to.have.length(2);
    //        console.log(result[0]);
    //        console.log(result[1]);
    //      });
    REQUIRE(oss.str() == "18488821436036968639067232489934022592333274628566486098353443781605964295553");
    REQUIRE(oss2.str() == "7774746543242992034824500334882847626558424832512738634355427079977301983471");
}
