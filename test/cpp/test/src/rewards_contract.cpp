#include <iostream>
#include <limits>
#include <chrono>

#include "ethyl/provider.hpp"
#include "ethyl/signer.hpp"
#include "service_node_rewards/config.hpp"
#include "service_node_rewards/service_node_rewards_contract.hpp"
#include "service_node_rewards/erc20_contract.hpp"
#include "service_node_rewards/service_node_list.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

const auto& config = ethbls::get_config(ethbls::network_type::LOCAL);
auto provider = std::make_shared<Provider>("Client", std::string(config.RPC_URL));

std::string contract_address = provider->getContractDeployedInLatestBlock();

ServiceNodeRewardsContract rewards_contract(contract_address, provider);
Signer signer(provider);    
std::vector<unsigned char> seckey = utils::fromHexString(std::string(config.PRIVATE_KEY));
//const std::string senderAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const std::string senderAddress = signer.addressFromPrivateKey(seckey);

std::string erc20_address = utils::trimAddress(rewards_contract.designatedToken());
ERC20Contract erc20_contract(erc20_address, provider);
std::string snapshot_id = provider->evm_snapshot();

TEST_CASE( "Rewards Contract", "[ethereum]" ) {
    bool success_resetting_to_snapshot = provider->evm_revert(snapshot_id);
    snapshot_id = provider->evm_snapshot();
    REQUIRE(success_resetting_to_snapshot);

    // Check rewards contract is responding and set to zero
    REQUIRE(rewards_contract.serviceNodesLength() == 0);
    REQUIRE(contract_address != "");

    // Approve our contract and make sure it was successful
    auto tx = erc20_contract.approve(contract_address, std::numeric_limits<std::uint64_t>::max());;
    auto hash = signer.sendTransaction(tx, seckey);
    REQUIRE(hash != "");
    REQUIRE(provider->transactionSuccessful(hash));

    // Start our contract
    tx = rewards_contract.start();;
    hash = signer.sendTransaction(tx, seckey);
    REQUIRE(hash != "");
    REQUIRE(provider->transactionSuccessful(hash));

    SECTION( "Add a public key to the smart contract" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(1);
        for(auto& node : snl.nodes) {
            const auto pubkey              = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx                             = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig");
            hash                           = signer.sendTransaction(tx, seckey);
            REQUIRE(hash != "");
            REQUIRE(provider->transactionSuccessful(hash));
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 1);

        // NOTE: Verify the service node stored on the EVM
        const ServiceNode& sn01    = snl.nodes[0];
        uint64_t           snIndex = rewards_contract.serviceNodeIDs(sn01.getPublicKey());
        REQUIRE(snIndex == 1); // First service node should be allocated index 1

        ContractServiceNode sn01InContract = rewards_contract.serviceNodes(snIndex);
        REQUIRE(sn01InContract.next == std::numeric_limits<uint64_t>::max());
        REQUIRE(sn01InContract.prev == std::numeric_limits<uint64_t>::max());

        // NOTE: Verify the ethereum address is correct
        std::array<unsigned char, 20> walletPKeyHex = signer.secretKeyToAddress(seckey);
        REQUIRE(sn01InContract.recipient             == walletPKeyHex);

        // NOTE: Verify the BLS key
        REQUIRE(sn01InContract.pubkey                == sn01.getPublicKey());

        // NOTE: Verify metadata
        REQUIRE(sn01InContract.leaveRequestTimestamp == 0);

        std::string stakingRequirementHex = utils::padTo32Bytes(utils::decimalToHex(ServiceNodeRewardsContract::STAKING_REQUIREMENT));
        REQUIRE(sn01InContract.deposit == stakingRequirementHex);
    }

    SECTION( "Add several public keys to the smart contract and check aggregate pubkey" ) {
        ServiceNodeList snl(2);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            hash = signer.sendTransaction(tx, seckey);
            REQUIRE(hash != "");
            REQUIRE(provider->transactionSuccessful(hash));
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and liquidate one of them with everyone signing (including the liquidated node)" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size());
        const auto [pubkey, sig] = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(service_node_to_remove, pubkey, sig, {});
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and liquidate one of them with a single non signer" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto [pubkey, sig] = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(service_node_to_remove, pubkey, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and try liquidate one of them with a not enough signers" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 2);
        const auto [pubkey, sig] = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(service_node_to_remove, pubkey, sig, {});
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Initiate remove public key with correct signer" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
    }

    SECTION( "Initiate remove public key with incorrect signer" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        std::vector<unsigned char> badseckey = utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        REQUIRE_THROWS(signer.sendTransaction(tx, badseckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
    }

    SECTION( "Remove public key after wait time should fail if node hasn't initiated removal" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.removeBLSPublicKeyAfterWaitTime(service_node_to_remove);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
    }

    SECTION( "Remove public key after wait time should fail if not enough time has passed since node initiated removal" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        tx = rewards_contract.removeBLSPublicKeyAfterWaitTime(service_node_to_remove);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
    }

    SECTION( "Remove public key after wait time should succeed if enough time has passed since node initiated removal" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        // Fast forward 31 days
        provider->evm_increaseTime(std::chrono::hours(31 * 24));
        tx = rewards_contract.removeBLSPublicKeyAfterWaitTime(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and remove one of them with a single non signer" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto [pubkey, sig] = snl.removeNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.removeBLSPublicKeyWithSignature(service_node_to_remove, pubkey, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and try remove one of them not enough signers" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 2);
        const auto [pubkey, sig] = snl.removeNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.removeBLSPublicKeyWithSignature(service_node_to_remove, pubkey, sig, non_signers);
        REQUIRE_THROWS(signer.sendTransaction(tx, seckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and update the rewards of one of them" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
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
        REQUIRE(provider->transactionSuccessful(hash));
        recipient = rewards_contract.viewRecipientData(senderAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == 0);
    }

    SECTION( "Add several public keys to the smart contract and update the rewards without enough signers and expect fail" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
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
    }

    SECTION( "Add several public keys to the smart contract and update the rewards of one of them and successfully claim the rewards" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        std::vector<unsigned char> secondseckey = utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
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
        REQUIRE(provider->transactionSuccessful(hash));

        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == recipientAmount);

        auto recipient = rewards_contract.viewRecipientData(recipientAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == amount);
    }

    SECTION( "Add LOTS of public keys to the smart contract and update the rewards of one of them and successfully claim the rewards" ) {
        SUCCEED("Complex test case runs too long on github worker");
        return;
        ServiceNodeList snl(2000);
        for(auto& node : snl.nodes) {
            tx = erc20_contract.approve(contract_address, std::numeric_limits<std::uint64_t>::max());;
            hash = signer.sendTransaction(tx, seckey);
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address, senderAddress, "pubkey");
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession, "pubkey", "sig", 0);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 2000);
        std::vector<unsigned char> secondseckey = utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        const std::string recipientAddress = signer.secretKeyToAddressString(secondseckey);
        const uint64_t recipientAmount = 1;
        const auto signers = snl.randomSigners(snl.nodes.size() - 299);
        const auto sig = snl.updateRewardsBalance(recipientAddress, recipientAmount, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.updateRewardsBalance(recipientAddress, recipientAmount, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        uint64_t amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == 0);

        tx = rewards_contract.claimRewards();
        hash = signer.sendTransaction(tx, secondseckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));

        amount = erc20_contract.balanceOf(recipientAddress);
        REQUIRE(amount == recipientAmount);

        auto recipient = rewards_contract.viewRecipientData(recipientAddress);
        REQUIRE(recipient.rewards == recipientAmount);
        REQUIRE(recipient.claimed == amount);
    }
}
