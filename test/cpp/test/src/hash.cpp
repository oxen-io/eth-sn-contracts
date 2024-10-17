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

std::array<std::string, 4> convertToHexStrings(const uint8_t md[128]) {
    std::array<std::string, 4> result;
    for (size_t i = 0; i < result.max_size(); ++i) {
        std::stringstream ss;
        ss << "0x";
        for (size_t j = 0; j < 32; ++j) {
            ss << std::setfill('0') << std::setw(2) << std::hex << static_cast<int>(md[i * 32 + j]);
        }
        result[i] = ss.str();
    }
    return result;
}

TEST_CASE("Expand message using Keccak256 via 'expand_mesage_xmd'", "[RFC9380 hashToField]") {
    assert(DOMAIN_SEPARATION_TAG_BYTES32.size() == 32
          && "The domain separation tag must be 32 bytes to match the Solidity implementation and produce the same results.");

    uint8_t md[128];
    utils::ExpandMessageXMDKeccak256(
        md,
        std::span(reinterpret_cast<const uint8_t *>(MESSAGE.data()),                       MESSAGE.size()),
        std::span(reinterpret_cast<const uint8_t *>(DOMAIN_SEPARATION_TAG_BYTES32.data()), DOMAIN_SEPARATION_TAG_BYTES32.size()));

    const auto hexStrings = convertToHexStrings(md);

    // NOTE: Values calculated via JS unit-test, see: eth-sn-contracts/test/unit-js/BN256G2.js
    INFO("Check that the hardcoded DST did not change in the Solidity implementation. The strings we compare against here were generated out-of-band.");
    CHECK(hexStrings[0] == "0xa9289d6c3626c2275c7f94a2aec2b47e90522afcfacea9d7d2d6d758bfcd0209");
    CHECK(hexStrings[1] == "0xe929d19bf0b1b42ec2674bc2d6395aa7a1d5988766413feb1aa4dc9c2e87a15d");
    CHECK(hexStrings[2] == "0xd34bd9627c1e82adcdb3359afde8ddc5946db33c4255c47497956d677155af6b");
    CHECK(hexStrings[3] == "0x47debeec9747b0b08909e419594a087497df70f8b60fdc66ebb577dab9a33696");
}

TEST_CASE("Hash to FP2", "[RFC9380 hashToField]") {
    bls::init(mclBn_CurveSNARK1);
    uint8_t md[128];
    utils::ExpandMessageXMDKeccak256(
        md,
        std::span(reinterpret_cast<const uint8_t *>(MESSAGE.data()),                       MESSAGE.size()),
        std::span(reinterpret_cast<const uint8_t *>(DOMAIN_SEPARATION_TAG_BYTES32.data()), DOMAIN_SEPARATION_TAG_BYTES32.size()));

    // NOTE: Do H(m||i) => (x1, x2, b)
    mcl::bn::Fp x[2];
    bool converted;
    x[0].setBigEndianMod(&converted, &md[0], 48);
    assert(converted); (void)converted;
    x[1].setBigEndianMod(&converted, &md[48], 48);
    assert(converted); (void)converted;

    // NOTE: Extract 'b'
    bool b = ((md[127] & 1) == 1);

    std::ostringstream oss;
    x[0].save(&converted, oss, mcl::IoAuto);
    std::ostringstream oss2;
    x[1].save(&converted, oss2, mcl::IoAuto);

    // NOTE: Values calculated via JS unit-test, see: eth-sn-contracts/test/unit-js/BN256G2.js
    CHECK(oss.str()  == "307410635215970536626579586125711284326114787973043528925905382633054236085");
    CHECK(oss2.str() == "1183035087006320090803410940370628752170722813268233981705860145243604330069");
    CHECK(b == false);
}

TEST_CASE("Zellic Test Vector", "FQ2Sqrt") {
    // NOTE: Load test vector from Zellic. See eth-sn-contracts/test/unit-js/BN256G2.js
    mcl::Fp2T<mcl::bn::Fp> x;
    static constexpr std::string_view input = "18400763209162137698378342072679747343805045379991482883044659141807904813804 3757716903061301937348252070019908304499894848840852657694527662312163652493";
    x.setStr(std::string(input), mcl::IoDec);

    // NOTE: Do the square root
    mcl::Fp2T<mcl::bn::Fp> y;
    bool rootExists = mcl::Fp2T<mcl::bn::Fp>::squareRoot(y, x);
    CHECK(rootExists);

    // NOTE: Extract the root(s) from the operation
    std::string root0;
    {
        std::ostringstream oss;
        bool b;
        y.save(&b, oss, mcl::IoDec);
        CHECK(b);
        root0 = oss.str();
    }

    std::string root1;
    {
        mcl::Fp2T<mcl::bn::Fp> neg_y = -y;
        std::ostringstream oss;
        bool b;
        neg_y.save(&b, oss, mcl::IoDec);
        CHECK(b);
        root1 = oss.str();
        oss.clear();
    }

    // NOTE: Verify the result
    static constexpr std::string_view ROOT_0 = "21113773905939110219807704586191458336348141462234245963448200970029289972960 4757623815106826332652416853619432081835467211624617316558602106633360047377";
    static constexpr std::string_view ROOT_1 = "774468965900165002438701159065816752348169695063577699240836924615936235623 17130619056732448889593988891637843006860843945673206346130435788011866161206";
    CHECK(root0 == ROOT_0);
    CHECK(root1 == ROOT_1);
}

TEST_CASE("Test Vector 0 & 1", "FQ2Sqrt") {
    // NOTE: Load test vector. See eth-sn-contracts/test/unit-js/BN256G2.js
    struct TestVector {
        std::string_view input;
        std::string_view root;
        std::string_view neg_root;
    } constexpr static TEST_VECTORS[] = {
        {
            /*input*/    "18643117260133094081555630496908182148979888402907667429281989499686433042481 18767426827650792022715527615257676532671283520119768371866051896505585913537",
            /*root*/     "13983740723413048141287686746094829568564621238524191737326450062318360253841 7253166406823230892838512371946295413549476296573503802098707278836650652634",
            /*neg_root*/ "7904502148426227080958718999162445520131689918773631925362587832326865954742 14635076465016044329407893373310979675146834860724319860590330615808575555949",
        },
        {
            /*input*/    "8003427931889017305260233532064766566259865014312993643669489451621672874553 8255214349881287197796283279515869829321316620831837079694717882055223224849",
            /*root*/     "16601660172989674590467103759517356028828864343517310912312924127793849257441 7249251494535356504402176277173612222981755570353172297173865703654518619480",
            /*neg_root*/ "5286582698849600631779301985739919059867446813780512750376113766851376951142 14638991377303918717844229468083662865714555586944651365515172190990707589103",
        },
    };

    for (size_t index = 0; index < sizeof(TEST_VECTORS)/sizeof(TEST_VECTORS[0]); index++) {
        const TestVector &vector = TEST_VECTORS[index];
        mcl::Fp2T<mcl::bn::Fp> x;
        x.setStr(std::string(vector.input), mcl::IoDec);

        // NOTE: Do the square root
        mcl::Fp2T<mcl::bn::Fp> y;
        bool rootExists = mcl::Fp2T<mcl::bn::Fp>::squareRoot(y, x);
        CHECK(rootExists);

        // NOTE: Extract the root(s) from the operation
        std::string root0;
        {
            std::ostringstream oss;
            bool b;
            y.save(&b, oss, mcl::IoDec);
            CHECK(b);
            root0 = oss.str();
        }

        std::string root1;
        {
            mcl::Fp2T<mcl::bn::Fp> neg_y = -y;
            std::ostringstream oss;
            bool b;
            neg_y.save(&b, oss, mcl::IoDec);
            CHECK(b);
            root1 = oss.str();
            oss.clear();
        }

        // NOTE: Verify the result
        INFO("Test vector " << index << " failed, positive root FQ2Sqrt did not match");
        CHECK(root0 == vector.root);

        INFO("Test vector " << index << " failed, negative root FQ2Sqrt did not match");
        CHECK(root1 == vector.neg_root);
    }
}
