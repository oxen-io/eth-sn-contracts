#include <iostream>
#include <limits>
#include <chrono>

#include "ethyl/provider.hpp"
#include "ethyl/signer.hpp"
#include "ethyl/utils.hpp"
#include "service_node_rewards/config.hpp"
#include "service_node_rewards/service_node_rewards_contract.hpp"
#include "service_node_rewards/erc20_contract.hpp"
#include "service_node_rewards/service_node_list.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

ethbls::network_config config;

auto client_ptr = ethyl::Provider::make_provider();
auto& defaultProvider = *client_ptr;
ethyl::Signer signer;
std::string contract_address;
std::string erc20_address;
std::string senderAddress;
std::string snapshot_id;

ERC20Contract erc20_contract;
ServiceNodeRewardsContract rewards_contract;

std::vector<unsigned char> seckey;


int main(int argc, char *argv[]) {

    // NOTE: Setup default provider
    config = ethbls::get_config(ethbls::network_type::LOCAL);
    std::cout << "Note to run these tests, ensure that a local Ethereum development network is running at " << config.RPC_URL << "\n";

    defaultProvider.addClient("Client", std::string(config.RPC_URL));
    signer.provider->addClient("Client", std::string(config.RPC_URL));
    erc20_contract.provider.addClient("Client", std::string(config.RPC_URL));
    rewards_contract.provider.addClient("Client", std::string(config.RPC_URL));

    // NOTE: The SN rewards contract has a deterministic deployment address
    // because we use a pre-determined debug wallet provided by Hardhat.
    contract_address = "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707";

    // NOTE: Setup keys
    seckey        = ethyl::utils::fromHexString(std::string(config.PRIVATE_KEY));
    senderAddress = signer.secretKeyToAddressString(seckey);

    // NOTE: Configure the contracts
    rewards_contract.contractAddress = contract_address;
    erc20_address                    = ethyl::utils::trimAddress(rewards_contract.designatedToken());
    erc20_contract.contractAddress   = erc20_address;

    snapshot_id = defaultProvider.evm_snapshot();
    int result  = Catch::Session().run(argc, argv);
    return result;
}

static void resetContractToSnapshot()
{
    REQUIRE(defaultProvider.evm_revert(snapshot_id));
}

// Given the service node list and the state of the list derived in C++, verify
// that the smart contract's service node list matches what we expect it to be.
static void verifyEVMServiceNodesAgainstCPPState(const ServiceNodeList& snl)
{
    // NOTE: Collect SNs from smart contract
    std::vector<ContractServiceNode>                  snInContract;
    std::unordered_map<uint64_t, ContractServiceNode> snInContractMap;
    {
        snInContract.reserve(1 /*sentinel*/ + snl.nodes.size());
        snInContract.push_back(rewards_contract.serviceNodes(0)); // Collect sentinel

        for (size_t index = 0; index < snl.nodes.size(); index++) {
            auto&    cppNode = snl.nodes[index];
            uint64_t snID    = rewards_contract.serviceNodeIDs(cppNode.getPublicKey());
            snInContract.push_back(rewards_contract.serviceNodes(snID));
            snInContractMap[snID] = snInContract.back();
        }
    }

    const ServiceNode sentinelCppNode = {};
    REQUIRE(1 /*sentinel*/ + snl.nodes.size() == snInContract.size());

    std::string const STAKING_REQUIREMENT_HEX = ethyl::utils::padTo32Bytes(ethyl::utils::decimalToHex(ServiceNodeRewardsContract::STAKING_REQUIREMENT));

    for (size_t index = 0; index < snl.nodes.size(); index++) {
        const ServiceNode&         cppNode = snl.nodes[index];
        const ContractServiceNode& ethNode = snInContractMap[cppNode.service_node_id];

        // NOTE: Verify the ethereum address is correct
        {
            std::array<unsigned char, 20> walletPKeyHex = signer.secretKeyToAddress(seckey);
            REQUIRE(ethNode.recipient == walletPKeyHex);
        }

        // NOTE: Verify metadata
        // TODO: Synchronise leave request timestamp into C++ representation
        // REQUIRE(ethNode.leaveRequestTimestamp == 0);

        // NOTE: Verify BLS key on the contract matches the C++ key
        REQUIRE(ethNode.pubkey == cppNode.getPublicKey());

        // NOTE: Verify the linked-list of service nodes. The SNL on the C++
        // side is the order of the linked list because we manually mirror the
        // operations to the C++ side.
        {
            // NOTE: Grab the next/prev nodes as determined by the C++ code
            const ServiceNode& nextCppNode = (index + 1 < snl.nodes.size()) ? snl.nodes[index + 1] : sentinelCppNode;
            const ServiceNode& prevCppNode = (index > 0)                    ? snl.nodes[index - 1] : sentinelCppNode;

            INFO("Service node at index " << index << " had linked list links that did not match the expected values\n"
                 << "  next: " << ethNode.next << " (expected: " << nextCppNode.service_node_id << ")\n"
                 << "  prev: " << ethNode.prev << " (expected: " << prevCppNode.service_node_id << ")");
            REQUIRE(ethNode.next == nextCppNode.service_node_id);
            REQUIRE(ethNode.prev == prevCppNode.service_node_id);
        }

        // NOTE: Verify the staking requirement
        {
            INFO("Staking requirement did not match, ours was '" << STAKING_REQUIREMENT_HEX
                 << "'. The contract reported '" << ethNode.deposit
                 << "': Check if scripts/deploy-local-testnet.js requirement matches the hardcoded staking amount at ServiceNodeRewardsContract::STAKING_REQUIREMENT.");
            REQUIRE(ethNode.deposit == STAKING_REQUIREMENT_HEX);
        }
    }
}

size_t test_count{0};
TEST_CASE( "Rewards Contract", "[ethereum]" ) {
    bool success_resetting_to_snapshot = defaultProvider.evm_revert(snapshot_id);
    snapshot_id = defaultProvider.evm_snapshot();
    REQUIRE(success_resetting_to_snapshot);

    // Check rewards contract is responding and set to zero
    REQUIRE(rewards_contract.serviceNodesLength() == 0);
    REQUIRE(contract_address != "");

    // Approve our contract and make sure it was successful
    auto tx = erc20_contract.approve(contract_address, std::numeric_limits<std::uint64_t>::max());;
    auto hash = signer.sendTransaction(tx, seckey);
    REQUIRE(hash != "");
    REQUIRE(defaultProvider.transactionSuccessful(hash));

    // Start our contract
    tx = rewards_contract.start();;
    hash = signer.sendTransaction(tx, seckey);
    REQUIRE(hash != "");
    REQUIRE(defaultProvider.transactionSuccessful(hash));
    SECTION( "Add a public key to the smart contract" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);

        ServiceNodeList snl(1);
        for(auto& node : snl.nodes) {
            const auto pubkey              = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx                             = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            hash                           = signer.sendTransaction(tx, seckey);
            REQUIRE(hash != "");
            REQUIRE(defaultProvider.transactionSuccessful(hash));
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 1);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and check aggregate pubkey" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(2);
        for(auto& node : snl.nodes) {
            const auto pubkey              = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx                             = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            hash                           = signer.sendTransaction(tx, seckey);
            REQUIRE(hash != "");
            REQUIRE(defaultProvider.transactionSuccessful(hash));
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        REQUIRE(rewards_contract.aggregatePubkeyString() == "0x" + snl.aggregatePubkeyHex());

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and liquidate one of them with everyone signing (including the liquidated node)" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size());
        const auto [pubkey, timestamp, sig] = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(pubkey, timestamp, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkeyString() == "0x" + snl.aggregatePubkeyHex());

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and liquidate one of them with a single non signer" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto [pubkey, timestamp, sig] = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(pubkey, timestamp, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkeyString() == "0x" + snl.aggregatePubkeyHex());

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and try liquidate one of them with a not enough signers" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 2);
        const auto [pubkey, timestamp, sig] = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(pubkey, timestamp, sig, non_signers);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        REQUIRE(rewards_contract.aggregatePubkeyString() == "0x" + snl.aggregatePubkeyHex());

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Initiate remove public key with correct signer" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Initiate remove public key with incorrect signer" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        std::vector<unsigned char> badseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        REQUIRE_THROWS(signer.sendTransaction(tx, badseckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Remove public key after wait time should fail if node hasn't initiated removal" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.removeBLSPublicKeyAfterWaitTime(service_node_to_remove);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Remove public key after wait time should fail if not enough time has passed since node initiated removal" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        tx = rewards_contract.removeBLSPublicKeyAfterWaitTime(service_node_to_remove);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Remove public key after wait time should succeed if enough time has passed since node initiated removal" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        // Fast forward 31 days
        defaultProvider.evm_increaseTime(std::chrono::hours(31 * 24));
        tx = rewards_contract.removeBLSPublicKeyAfterWaitTime(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkeyString() == "0x" + snl.aggregatePubkeyHex());

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and remove one of them with a single non signer" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto [pubkey, timestamp, sig] = snl.removeNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.removeBLSPublicKeyWithSignature(pubkey, timestamp, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkeyString() == "0x" + snl.aggregatePubkeyHex());

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and try remove one of them not enough signers" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 2);
        const auto [pubkey, timestamp, sig] = snl.removeNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.removeBLSPublicKeyWithSignature(pubkey, timestamp, sig, non_signers);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        REQUIRE(rewards_contract.aggregatePubkeyString() == "0x" + snl.aggregatePubkeyHex());

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and update the rewards of one of them" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        auto recipient = rewards_contract.viewRecipientData(senderAddress);
        REQUIRE(recipient.rewards == 0);
        REQUIRE(recipient.claimed == 0);
        const uint64_t recipientAmount = 1;
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto sig = snl.updateRewardsBalance(senderAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(senderAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        recipient = rewards_contract.viewRecipientData(senderAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == 0);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and update the rewards without enough signers and expect fail" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        auto recipient = rewards_contract.viewRecipientData(senderAddress);
        REQUIRE(recipient.rewards == 0);
        REQUIRE(recipient.claimed == 0);
        const uint64_t recipientAmount = 1;
        const auto signers = snl.randomSigners(snl.nodes.size() - 2);
        const auto sig = snl.updateRewardsBalance(senderAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(senderAddress, recipientAmount, sig, non_signers);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add several public keys to the smart contract and update the rewards of one of them and successfully claim the rewards" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 1;
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        tx = rewards_contract.claimRewards();
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));

        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == recipientAmount);

        auto recipient = rewards_contract.viewRecipientData(recipientAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == amount);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Successfully claim the rewards specifying the exact amount" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 1;
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        tx = rewards_contract.claimRewards(recipientAmount);
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));

        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == recipientAmount);

        auto recipient = rewards_contract.viewRecipientData(recipientAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == amount);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Successfully claim the rewards specifying a lower amount then maximum" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 2;
        const uint64_t lowerAmount = 1;
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        tx = rewards_contract.claimRewards(lowerAmount);
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));

        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == lowerAmount);

        auto recipient = rewards_contract.viewRecipientData(recipientAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == amount);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Fail to claim the rewards specifying a higher amount then maximum" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 2;
        const uint64_t higherAmount = 3;
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        tx = rewards_contract.claimRewards(higherAmount);
        REQUIRE_THROWS(signer.sendTransaction(tx, secondseckey));

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Claim too many rewards in a single transaction and trigger rate limiter" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 3000000000000000;
        const auto signers = snl.randomSigners(snl.nodes.size());
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        tx = rewards_contract.claimRewards();
        REQUIRE_THROWS(signer.sendTransaction(tx, secondseckey));

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Claim too much rewards but over the waiting time should succeed" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 500000000000000;
        const auto signers = snl.randomSigners(snl.nodes.size());
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        const uint64_t secondRecipientAmount = 1100000000000000;
        tx = erc20_contract.transfer(contract_address, secondRecipientAmount);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));

        tx = rewards_contract.claimRewards();
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == recipientAmount);

        const auto secondSig = snl.updateRewardsBalance(recipientAddress, secondRecipientAmount, config.CHAIN_ID, contract_address, signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, secondRecipientAmount, secondSig, non_signers);
        hash = signer.sendTransaction(tx, secondseckey);
        // Fast forward 1 days
        defaultProvider.evm_increaseTime(std::chrono::hours(1 * 24));

        tx = rewards_contract.claimRewards();
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == secondRecipientAmount);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Claim too much rewards over two transactions and trigger rate limiter" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 500000000000000;
        const auto signers = snl.randomSigners(snl.nodes.size());
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        const uint64_t secondRecipientAmount = 1100000000000000;
        tx = erc20_contract.transfer(contract_address, secondRecipientAmount);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));

        tx = rewards_contract.claimRewards();
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == recipientAmount);

        const auto secondSig = snl.updateRewardsBalance(recipientAddress, secondRecipientAmount, config.CHAIN_ID, contract_address, signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, secondRecipientAmount, secondSig, non_signers);
        hash = signer.sendTransaction(tx, secondseckey);

        tx = rewards_contract.claimRewards();
        REQUIRE_THROWS(signer.sendTransaction(tx, secondseckey));

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

    SECTION( "Add LOTS of public keys to the smart contract and update the rewards of one of them and successfully claim the rewards" ) {
        SUCCEED("Complex test case runs too long on github worker");
        return;
        ServiceNodeList snl(2000);
        for(auto& node : snl.nodes) {
            tx = erc20_contract.approve(contract_address, std::numeric_limits<std::uint64_t>::max());;
            hash = signer.sendTransaction(tx, seckey);
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey" + std::to_string(node.service_node_id));
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey" + std::to_string(node.service_node_id), "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 2000);
        std::vector<unsigned char> secondseckey = ethyl::utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 1;
        const auto signers = snl.randomSigners(snl.nodes.size() - 299);
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        tx = rewards_contract.claimRewards();
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(defaultProvider.transactionSuccessful(hash));

        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == recipientAmount);

        auto recipient = rewards_contract.viewRecipientData(recipientAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == amount);

        verifyEVMServiceNodesAgainstCPPState(snl);
        resetContractToSnapshot();
    }

}
