#include <iostream>
#include <iomanip>

#include "service_node_rewards/ec_utils.hpp" // utils::Expand...
#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

// NOTE: Hardcoded msg/DST that matches the DST specified in JS unit-test, see:
// eth-sn-contracts/test/unit-js/BN256G2.js
std::string_view MESSAGE = "asdf";
std::string_view DOMAIN_SEPARATION_TAG_BYTES32 =
    "\xff\x54\x97\x7c\x9d\x08\xfb\x90\x98\xf6\xbe\xae\x0e\x46\x34\xcb\x9b\x2d\x4c\x2b\x9c\x86\xf0\xb3\xe2\xf2\xf0\x07\x3b\x73\xf5\x1c";

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

TEST_CASE("Expand message using Keccak256 via 'expand_mesage_xmd'", "[RFC9380 hashToField]") {
    assert(DOMAIN_SEPARATION_TAG_BYTES32.size() == 32
          && "The domain separation tag must be 32 bytes to match the Solidity implementation and produce the same results.");

    uint8_t md[96];
    utils::ExpandMessageXMDKeccak256(
        md,
        std::span(reinterpret_cast<const uint8_t *>(MESSAGE.data()),                       MESSAGE.size()),
        std::span(reinterpret_cast<const uint8_t *>(DOMAIN_SEPARATION_TAG_BYTES32.data()), DOMAIN_SEPARATION_TAG_BYTES32.size()));

    const auto hexStrings = convertToHexStrings(md);

    // NOTE: Values calculated via JS unit-test, see: eth-sn-contracts/test/unit-js/BN256G2.js
    INFO("Check that the hardcoded DST did not change in the Solidity implementation. The strings we compare against here were generated out-of-band.");
    CHECK(hexStrings[0] == "0xe8f4d933efbcf56796fe680e8d947406e18862ab351bea98c5d9f8888080fe6f");
    CHECK(hexStrings[1] == "0x097596243f18b9fa9d600eb8346663987b0153a3781e4a7b54bbbd833c00166c");
    CHECK(hexStrings[2] == "0x24824cfba40d05f96f25933446d22f4e2c4323fa0f13904a264439aea47d28be");
}

TEST_CASE("Hash to FP2", "[RFC9380 hashToField]") {
    bls::init(mclBn_CurveSNARK1);
    uint8_t md[96];
    utils::ExpandMessageXMDKeccak256(
        md,
        std::span(reinterpret_cast<const uint8_t *>(MESSAGE.data()),                       MESSAGE.size()),
        std::span(reinterpret_cast<const uint8_t *>(DOMAIN_SEPARATION_TAG_BYTES32.data()), DOMAIN_SEPARATION_TAG_BYTES32.size()));

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

    // NOTE: Values calculated via JS unit-test, see: eth-sn-contracts/test/unit-js/BN256G2.js
    CHECK(oss.str()  == "11032720900463547873271743099548770716954083165825879766348225717865290248407");
    CHECK(oss2.str() == "15644586462817709158587850387782908059942803533371602959682274737078222802151");
}
