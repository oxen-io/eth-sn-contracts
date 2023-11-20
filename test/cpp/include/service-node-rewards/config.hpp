// Copyright (c) 2014-2019, The Monero Project
//
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of
//    conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice, this list
//    of conditions and the following disclaimer in the documentation and/or other
//    materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its contributors may be
//    used to endorse or promote products derived from this software without specific
//    prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
// THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
// THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Parts of this file are originally copyright (c) 2012-2013 The Cryptonote developers

#pragma once

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <ratio>
#include <stdexcept>
#include <string>
#include <string_view>

using namespace std::literals;

namespace ethbls {

enum class network_type : uint8_t { ARBITRUM = 0, SEPOLIA = 1, GANACHE = 2, UNDEFINED = 255 };

constexpr network_type network_type_from_string(std::string_view s) {
    if (s == "arbitrum")
        return network_type::ARBITRUM;

    if (s == "sepolia")
        return network_type::SEPOLIA;

    if (s == "ganache")
        return network_type::GANACHE;

    return network_type::UNDEFINED;
}

constexpr std::string_view network_type_to_string(network_type t) {
    switch (t) {
        case network_type::ARBITRUM: return "arbitrum";
        case network_type::SEPOLIA: return "sepolia";
        case network_type::GANACHE: return "ganache";
        default: return "undefined";
    }
    return "undefined";
}

// Various configuration defaults and network-dependent settings
namespace config {
    namespace arbitrum {
        inline constexpr std::string_view RPC_URL = "https://arb1.arbitrum.io/rpc";
        inline constexpr uint32_t CHAIN_ID = 42161;
        inline constexpr std::string_view BLOCK_EXPLORER_URL = "https://arbiscan.io";
        inline constexpr std::string_view OFFICIAL_WEBSITE = "https://portal.arbitrum.one";
        inline constexpr std::string_view BLS_CONTRACT_ADDRESS = "";
        inline constexpr std::string_view MERKLE_CONTRACT_ADDRESS = "";
    }  // namespace arbitrum
    namespace sepolia {
        inline constexpr std::string_view RPC_URL = "https://rpc.sepolia.org";
        //inline constexpr std::string_view RPC_URL = "https://ethereum-sepolia.blockpi.network/v1/rpc/public";
        inline constexpr uint32_t CHAIN_ID = 11155111;
        inline constexpr std::string_view BLOCK_EXPLORER_URL = "https://sepolia.etherscan.io/";
        inline constexpr std::string_view OFFICIAL_WEBSITE = "https://sepolia.dev/";
        inline constexpr std::string_view BLS_CONTRACT_ADDRESS = "0xf85468442B4904cde8D526745369C07CE8F612eA";
        inline constexpr std::string_view MERKLE_CONTRACT_ADDRESS = "0xf85468442B4904cde8D526745369C07CE8F612eA";
    }  // namespace sepolia 
    namespace ganache {
        inline constexpr std::string_view RPC_URL = "127.0.0.1:8545";
        inline constexpr uint32_t CHAIN_ID = 1337;
        inline constexpr std::string_view BLOCK_EXPLORER_URL = "";
        inline constexpr std::string_view OFFICIAL_WEBSITE = "";
        inline constexpr std::string_view BLS_CONTRACT_ADDRESS = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
        inline constexpr std::string_view MERKLE_CONTRACT_ADDRESS = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";
    }  // namespace sepolia 
}  // namespace config

struct network_config {
    std::string_view RPC_URL;
    uint32_t CHAIN_ID;
    std::string_view BLOCK_EXPLORER_URL;
    std::string_view OFFICIAL_WEBSITE;
    std::string_view BLS_CONTRACT_ADDRESS;
    std::string_view MERKLE_CONTRACT_ADDRESS;
};

inline constexpr network_config arbitrum_config{
        config::arbitrum::RPC_URL,
        config::arbitrum::CHAIN_ID,
        config::arbitrum::BLOCK_EXPLORER_URL,
        config::arbitrum::OFFICIAL_WEBSITE,
        config::arbitrum::BLS_CONTRACT_ADDRESS,
        config::arbitrum::MERKLE_CONTRACT_ADDRESS,
};

inline constexpr network_config sepolia_config{
        config::sepolia::RPC_URL,
        config::sepolia::CHAIN_ID,
        config::sepolia::BLOCK_EXPLORER_URL,
        config::sepolia::OFFICIAL_WEBSITE,
        config::sepolia::BLS_CONTRACT_ADDRESS,
        config::sepolia::MERKLE_CONTRACT_ADDRESS,
};

inline constexpr network_config ganache_config{
        config::ganache::RPC_URL,
        config::ganache::CHAIN_ID,
        config::ganache::BLOCK_EXPLORER_URL,
        config::ganache::OFFICIAL_WEBSITE,
        config::ganache::BLS_CONTRACT_ADDRESS,
        config::ganache::MERKLE_CONTRACT_ADDRESS,
};

inline constexpr const network_config& get_config(network_type nettype) {
    switch (nettype) {
        case network_type::ARBITRUM: return arbitrum_config;
        case network_type::SEPOLIA: return sepolia_config;
        case network_type::GANACHE: return ganache_config;
        default: throw std::runtime_error{"Invalid network type"};
    }
}

}  // namespace ethbls
